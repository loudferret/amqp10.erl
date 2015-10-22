
-module(amqp1_auth_sasl_SUITE).

-compile(export_all).

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("amqp1.hrl").
-include("amqp1_priv.hrl").
-include("test.hrl").

-define(TESTED, amqp1_auth_sasl).
-define(TSTCMD5, amqp1_auth_sasl_crammd5).

all() -> 
	[	  incoming_sasl_anonym	
		, incoming_sasl_crammd5	
		, auth_anonymous
		, auth_crammd5_get_init
		, auth_crammd5_get_response
	]
	, {skip, not_needed}
	.

%% Fixtures %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Suite
init_per_suite(Config) ->
	ct:pal("==== TEST SUITE: ~s ====", [?MODULE_STRING]),
	Config.

end_per_suite(_Config) ->
	ct:pal("==== /TEST SUITE: ~s ===", [?MODULE_STRING]),
	ok.

%% Group
init_per_group(_, Config) ->
	Config.

end_per_group(_, Config) ->
	Config.

%% Case
init_per_testcase(TestCase, Config) ->
	ct:pal("==== TEST CASE: ~s ====",[TestCase]),
	Config.

end_per_testcase(TestCase, Config) ->
	ct:pal("==== /TEST CASE: ~s ===",[TestCase]),
	Config.


%% TEST Cases %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

auth_crammd5_get_response(_Config) ->
	Ch = cmd5_challenge(),
	ChF = #frame{type = ?SASL, channel = 0, body = p_sasl_challenge(Ch)},
	R = ?TSTCMD5:cmd5_response(the_acp(), Ch), 
	tool:mnew([{amqp1_net, [passthrough]}, {amqp1_framing, [passthrough]}]),
	%% Simply return original
	meck:expect(amqp1_framing, record_to_binary, fun(R) -> R end),
	meck:expect(amqp1_framing, frame_to_binary, fun(#frame{} = F) -> F end),
	meck:expect(amqp1_net, send,
		fun(_S, #frame{type = ?SASL, channel = 0, body = B}) ->
			?assertEqual(B#'v1_0.sasl_response'.response, {binary, R}),
			ok
		end),
	meck:expect(amqp1_net, recv, fun(_S, _TO) -> {ok, <<>>} end),
	?assertEqual(error, ?TSTCMD5:auth(self(), the_acp(), [[ChF]])),
	true = tool:mvalid([amqp1_net, amqp1_framing]),
	tool:munld(),
	ok.

auth_crammd5_get_init(_Config) ->
	tool:mnew([{amqp1_net, [passthrough]}, {amqp1_framing, [passthrough]}]),
	%% Simply return original
	meck:expect(amqp1_framing, record_to_binary, fun(R) -> R end),
	meck:expect(amqp1_framing, frame_to_binary, fun(#frame{} = F) -> F end),
	meck:expect(amqp1_net, send,
		fun(_S, #frame{type = ?SASL, channel = 0, body = B}) ->
			{ok, HNS} = inet:gethostname(),
			?assertEqual(B#'v1_0.sasl_init'.mechanism, ?CRAMMD5),
			?assertEqual(B#'v1_0.sasl_init'.initial_response, undefined),
			?assertEqual(B#'v1_0.sasl_init'.hostname, iolist_to_binary(HNS)),
			ok
		end),
	meck:expect(amqp1_net, recv, fun(_S, _TO) -> {ok, <<>>} end),
	?assertEqual(error, ?TSTCMD5:auth(self(), the_acp(), [])),
	true = tool:mvalid([amqp1_net, amqp1_framing]),
	tool:munld(),
	ok.

auth_anonymous(_Config) ->
	tool:mnew([{amqp1_net, [passthrough]}, {amqp1_framing, [passthrough]}]),
	meck:expect(amqp1_net, send, fun(_S, ?AUTH_SASL) -> ok end),
	meck:expect(amqp1_net, recv, fun(_S, _TO) -> {ok, incoming} end),
	meck:expect(amqp1_framing, pick_frames,
				fun(incoming) ->
					ct:pal("pick_frames(incoming)"),
					in_frames
			   	end),
	meck:expect(amqp1_framing, parse_all_frames,
			   	fun(in_frames) -> 
					ct:pal("parse_all_frames(in_frames)"),
					frames_anonymous()
				end),
	meck:expect(amqp1_framing, binary_to_records,
				fun(sasl_mechanisms_anonymous) ->
					ct:pal("binary_to_records(sasl_mechanisms_anonymous)"),
					sasl_mechanisms_anonymous()
				end),
	?assertEqual(authenticated, ?TESTED:auth(self(), the_acp())),
	true = tool:mvalid([amqp1_net, amqp1_framing]),
	tool:munld(),
	ok.

incoming_sasl_crammd5(Config) ->
	{ok, D1} = tool:rtf("packet_03.bin", Config),
	ML = [amqp1_net, amqp1_auth_sasl_anonymous, amqp1_auth_sasl_crammd5],
	tool:mnew(ML),
	meck:expect(amqp1_net, send, fun(_S, ?AUTH_SASL) -> ok end),
	meck:expect(amqp1_net, recv, fun(_S, _TO) -> {ok, D1} end),
	meck:expect(amqp1_auth_sasl_anonymous, auth,
			   	fun(_S,_P,_FL) ->  ct:fail("ANONYMOUS") end),
	meck:expect(amqp1_auth_sasl_crammd5, auth, fun(_S,_P,_FL) -> ok end),
	?TESTED:auth(self(), the_acp()),
	true = tool:mvalid(ML),
	tool:munld(),
	ok.

incoming_sasl_anonym(Config) ->
	{ok, D1} = tool:rtf("packet_02.bin", Config),
	ML = [amqp1_net, amqp1_auth_sasl_anonymous, amqp1_auth_sasl_crammd5],
	tool:mnew(ML),
	meck:expect(amqp1_net, send, fun(_S, ?AUTH_SASL) -> ok end),
	meck:expect(amqp1_net, recv, fun(_S, _TO) -> {ok, D1} end),
	meck:expect(amqp1_auth_sasl_anonymous, auth, fun(_S,_P,_FL) -> ok end),
	meck:expect(amqp1_auth_sasl_crammd5, auth, fun(_S,_P,_FL) -> ct:fail("CRAM") end),
	?TESTED:auth(self(), the_acp()),
	true = tool:mvalid(ML),
	tool:munld(),
	ok.

%% Locals %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%	The server sends a base64-encoded string to the client. Before encoding, it
%	could be any random string, but the standard that currently defines CRAM-MD5
%	says that it is in the format of a Message-ID email header value (including
%	angle brackets) and includes an arbitrary string of random digits, a timestamp,
%	and the server's fully qualified domain name.
cmd5_challenge() ->
	Rand = crypto:rand_bytes(10),
	{MegaSecs, Secs, MicroSecs} = os:timestamp(),
	TS = (MegaSecs * 1000 * 1000 * 1000) + (Secs * 1000) + (MicroSecs div 1000),
	TSbin = integer_to_binary(TS),
	{ok, HN} = inet:gethostname(),
	HNbin = iolist_to_binary(HN),
	base64:encode(<<Rand/binary, TSbin/binary, HNbin/binary>>).

frames_crammd5() ->
	[?SASL, #frame{body = sasl_mechanisms_crammd5}].

frames_anonymous() ->
	[	?SASL,
		#frame{body = sasl_mechanisms_anonymous},
		?AMQP1_HEADER ].

sasl_mechanisms_crammd5() ->
	[#'v1_0.sasl_mechanisms'{sasl_server_mechanisms = {symbol, ?CRAMMD5}}].

sasl_mechanisms_anonymous() ->
	[#'v1_0.sasl_mechanisms'{sasl_server_mechanisms = {symbol, <<"ANONYMOUS">>}}].


%% -record('v1_0.sasl_init', {mechanism, initial_response, hostname})
p_sasl_init() ->
	amqp1_framing:record_to_binary(
		#'v1_0.sasl_init'{mechanism = {symbol,<<"ANONYMOUS">>},
						  initial_response = undefined,
						  hostname = undefined}).

%% -record('v1_0.sasl_mechanisms', {sasl_server_mechanisms})
p_one_mechanisms() ->
	amqp1_framing:record_to_binary(
		#'v1_0.sasl_mechanisms'{sasl_server_mechanisms = {symbol, <<"ANONYMOUS">>}}).

p_multiple_auth_mechanisms() ->
	Ms = #'v1_0.sasl_mechanisms'{sasl_server_mechanisms = {array, symbol,
							 [<<"ANONYMOUS">>, ?CRAMMD5]}},
	amqp1_framing:record_to_binary(Ms).

p_sasl_challenge(Ch) ->
	F = #'v1_0.sasl_challenge'{challenge = {binary, Ch}},
	%ct:pal("Challenge Frame:~n~p", [F]),
	amqp1_framing:record_to_binary(F).

p_sasl_outcome(C) -> p_sasl_outcome(C, undefined).
p_sasl_outcome(C, AD) ->
	F = #'v1_0.sasl_outcome'{code = C, additional_data = AD},
	amqp1_framing:record_to_binary(F).
	
the_acp() ->
	#amqp1_connection_parameters{host = "localhost", port = "5672",
			 user = <<"amqp1_test_usr">>, password = <<"amqp1_test_pwd">>}.


% end of file









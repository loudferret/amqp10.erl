
-module(amqp1_connection_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("amqp1.hrl").
-include("amqp1_priv.hrl").
-include("test.hrl").

-define(TESTED, amqp1_connection).

all() -> 
	[	connect_and_auth_sasl	]
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

connect_and_auth_sasl(_Config) ->
	%amqp1_comm_sup:start(),
	%amqp1_codec_sup:start(),
	tool:mnew([amqp1_comm_sup, amqp1_codec_sup]),
	meck:expect(amqp1_comm_sup, start_sender, fun(_S,_P,_DB) -> {ok, self()} end),
	meck:expect(amqp1_comm_sup, start_receiver, fun(_S,_P,_DB) -> {ok, self()} end),
	meck:expect(amqp1_codec_sup, start_codec, fun(_P,_SP) -> {ok, self()} end),
	?TESTED:init(params_qpid()),
	true = tool:mvalid([amqp1_comm_sup, amqp1_codec_sup]),
	meck:unload(),
	ok.

%% Locals %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

params_qpid() ->
	#amqp1_connection_parameters{host = "localhost",
								 port = 5672,
								 user = <<"guest">>,
								 password = <<"guest">>,
								 options = []}.

% end of file








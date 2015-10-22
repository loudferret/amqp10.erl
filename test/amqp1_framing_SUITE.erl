
-module(amqp1_framing_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").

-include("amqp1.hrl").
-include("amqp1_priv.hrl").
-include("test.hrl").

-define(TESTED, amqp1_framing).

all() -> 
	[	  p_sasl_init
		, p_flow
		, p_attach
		, p_open_begin
		, p_negotiation
		, enc_list
		, pick_frames
	]
	, [p_transfer]
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

pick_frames(_Config) ->
	RestBinShort = <<"X">>,
	RestBinLong = <<"AMQPBin">>,
	InBinShort = <<"AMQP", 3, 1, 0, 0, RestBinShort/binary>>,
	InBinLong = <<"AMQP", 3, 1, 0, 0, RestBinLong/binary>>,
	In2Frames = <<0,0,0,16,2,1,0,0,0,83,68,192,3,1,80,0,65,77,81,80,0,1,0,0>>,
	R2 = {[<<0,0,0,16,2,1,0,0,0,83,68,192,3,1,80,0>>, ?AMQP], <<>>},
	?assertEqual({[?SASL], RestBinShort}, ?TESTED:pick_frames(InBinShort)),
	?assertEqual({[?SASL], RestBinLong}, ?TESTED:pick_frames(InBinLong)),
	?assertEqual(R2, ?TESTED:pick_frames(In2Frames)),
	ok.

enc_list(_Config) ->
	MsE = #'v1_0.sasl_mechanisms'{sasl_server_mechanisms =
								 {array, symbol, [<<"A">>, <<"B">>]}},
	RcpE = amqp1_framing:record_to_recipe(MsE),
	ct:pal("RcpE: ~p", [RcpE]),
	IOBinE1 = amqp1_framing:recipe_to_binary(RcpE),
	ct:pal("IOBinE1: ~p", [IOBinE1]),
	IOBinE = amqp1_framing:record_to_binary(MsE),
	ct:pal("EEncoded: ~p", [iolist_to_binary(IOBinE)]),
	Ms = #'v1_0.sasl_mechanisms'{sasl_server_mechanisms = {array, symbol,
								 [<<"ANONYMOUS">>, ?CRAMMD5]}},
	Rcp = amqp1_framing:record_to_recipe(Ms),
	ct:pal("Rcp: ~p", [Rcp]),
	IOBin = amqp1_framing:record_to_binary(Ms),
	ct:pal("Encoded: ~p", [iolist_to_binary(IOBin)]),
	ok.
	

p_negotiation(Config) ->
	{ok, Data} = tool:rtf("packet_02.bin", Config),
	{PFL, <<>>} = ?TESTED:pick_frames(Data),
	?assertEqual(?SASL, hd(PFL)),
	ct:pal("PFL: ~p", [PFL]),
	
	BFL = ?TESTED:parse_all_frames(PFL),
	ct:pal("parse_all_frames -> BFL:~n~p", [BFL]),
	
	RCPL = [ ?TESTED:binary_to_recipe(FB) || #frame{body = FB} <- BFL ],
	ct:pal("binary_to_recipe -> RCPL:~n~p", [RCPL]),
	X = [[{described,{ulong,65},{list,[{symbol,<<"A1">>}]}}],
		 [{described,{ulong,65},{list,[{symbol,<<"A1">>},
									   {symbol,<<"A2">>},{symbol,<<"A3">>}]}}]
		],
	
	RECLa = [ ?TESTED:recipe_to_records(R) || [R] <- X ],
	ct:pal("recipe_to_records -> RECLa:~n~p", [RECLa]),

	RECL = [ ?TESTED:recipe_to_records(R) || [R] <- RCPL ],
	ct:pal("recipe_to_records -> RECL:~n~p", [RECL]),

	RL = [ ?TESTED:binary_to_records(FB) || #frame{body = FB} <- BFL ],
	ct:pal("binary_to_records -> RL:~n~p", [RL]),
	
	%% -record('v1_0.sasl_init', {mechanism, initial_response, hostname}).
	%% [#'v1_0.sasl_init'{{symbol,<<"ANONYMOUS">>},undefined,undefined}],
	ok.

p_open_begin(Config) ->
	{ok, DataOpen} = tool:rtf("open.bin", Config),
	{ok, DataBegin} = tool:rtf("begin.bin", Config),
	ExpOpen = [{described,{ulong,16},
			{list,[{utf8,<<"0509a950-7ec7-4b9e-9ddc-b394df8339e2">>},
				   {utf8,<<"localhost">>}]}}],
	ExpBegin = [{described,{ulong,17},
		   {list,[null,{uint,1},{uint,0},{uint,0},{uint,1024}]}}],
	{BFL, <<>>} = ?TESTED:pick_frames(<<DataOpen/binary, DataBegin/binary>>),
	FramesL = ?TESTED:parse_all_frames(BFL),
	RecipeL = [?TESTED:binary_to_recipe(FB) || #frame{body = FB} <- FramesL],
	?assertEqual([ExpOpen, ExpBegin], RecipeL),
	ok.

p_attach(Config) ->
	{ok, Data} = tool:rtf("attach.bin", Config),
	Exp = [{described,{ulong,18}, {list,[{utf8,<<"proton">>}, {uint,0}, false,
			{ubyte,2}, {ubyte,0},
		   	{described,{ulong,40},{list,[{utf8,<<"proton">>}]}},
		   	{described,{ulong,41},{list,[{utf8,<<"proton">>}]}},
		   	null,false, {uint,0}]}}],
	#frame{type = ?AMQP, body = BFB} = ?TESTED:parse_frame(Data),
	?assertEqual(Exp, ?TESTED:binary_to_recipe(BFB)),
	ok.

p_flow(Config) ->
	{ok, Data} = tool:rtf("flow.bin", Config),
	Exp = [{described,{ulong,19},
				{list,[null,{uint,2147483647},{uint,1},{uint,1}]}}],
	#frame{type = ?AMQP, body = BFB} = ?TESTED:parse_frame(Data),
	Recipe = ?TESTED:binary_to_recipe(BFB),
	?assertEqual(Exp, Recipe),
	ok.


p_sasl_init(Config) ->
	{ok, Data} = tool:rtf("sasl_init.bin", Config),
	Exp = [{described,{ulong,65},{list,[{symbol,<<"ANONYMOUS">>}]}}],
	{BFL, <<>>} = ?TESTED:pick_frames(Data),
	FramesL = ?TESTED:parse_all_frames(BFL),
	RecipeL = [?TESTED:binary_to_recipe(FB) || #frame{body = FB} <- FramesL],
	?assertEqual(Exp, hd(RecipeL)),
	ok.

p_transfer(Config) ->
	{ok, Data} = tool:rtf("transfer.bin", Config),
	{BFL, <<>>} = ?TESTED:pick_frames(Data),
	FramesL = ?TESTED:parse_all_frames(BFL),
	ct:pal("FramesL #~p", [length(FramesL)]),
	[RecipeL] = [?TESTED:binary_to_recipe(FB) || #frame{body = FB} <- FramesL],
	[ ct:pal("Recipe:~n~200p", [Recipe]) || Recipe <- RecipeL ],
	Recs = ?TESTED:binary_to_records(Data),
	ct:pal("Recs:~n~200p", [Recs]),
	ok.



%% Locals %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



% end of file








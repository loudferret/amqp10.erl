
-module(amqp1_session_process_SUITE).



-compile(export_all).

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("amqp1.hrl").
-include("amqp1_priv.hrl").
-include("test.hrl").

-define(TESTED, amqp1_session_process).

all() -> 
	[	  
	]
	, {skip, not_needed}
	, []
.  

%% Fixtures %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Suite
init_per_suite(Config) ->
	ct:pal("==== TEST SUITE: ~s ====", [?MODULE_STRING]),
	Config.

end_per_suite(_Config) ->
	ct:pal("==== /TEST SUITE: ~s ===", [?MODULE_STRING]),
	?TESTED:stop(),
	ok.

%% Group
init_per_group(_, Config) ->
	Config.

end_per_group(_, Config) ->
	Config.

%% Case
init_per_testcase(TestCase, Config) ->
	ct:pal("==== TEST CASE: ~s ====", [TestCase]),
	Config.

end_per_testcase(TestCase, Config) ->
	ct:pal("==== /TEST CASE: ~s ===", [TestCase]),
	Config.


%% TEST Cases %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%




%% Locals %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% end of file









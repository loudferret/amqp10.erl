
-module(amqp1_app_SUITE).

-compile(export_all).

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("amqp1.hrl").
-include("amqp1_priv.hrl").
-include("test.hrl").

-define(TESTED, amqp1_app).

all() -> 
	[	  app_start_stop
		, app_start_and_try_connect
		, start_stop_whole_skelet
		, start_connect_close_stop
		, start_connect_begin_close_stop
		, start_connect_begin_end_close_stop
		, multiple_opened_sessions
		, send_messssage
		, get_link_notFound
		, get_link
	]
	, [get_link, send_messssage]
	, {skip, not_needed}
	, [get_link_notFound, get_link]
	, [get_link]
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

get_link(_Config) ->
	TQ = <<"clTestQueue">>,
	GL = #get_link{role = ?ROLE_SENDER, node = TQ},
	ok = ?TESTED:start(),
	{ok, Conn} = amqp1:connect(params_qpid_cltest()),
	{ok, Sess} = amqp1_connection:begin_session(Conn),
	timer:sleep(2000),
	ct:pal("Conn ~p, Sess ~p, let's attach.", [Conn, Sess]),
	{ok, Link1} = amqp1_session:get_link(Sess, GL),
	{ok, Link2} = amqp1_session:get_link(Sess, GL),
	ct:pal("Link1 ~120p~nLink2 ~120p.", [Link1, Link2]),
	?assertEqual(Link1, Link2),
	timer:sleep(2000),
	ok = amqp1_session:end_session(Sess),
	ok = amqp1_connection:stop(Conn),
	ok.

get_link_notFound(_Config) ->
	TQ = <<">>> non-existen_queue_or_whatever_does_not_exist_in_server <<<">>,
	GL = #get_link{role = ?ROLE_SENDER, node = TQ},
	ok = ?TESTED:start(),
	{ok, Conn} = amqp1:connect(params_qpid()),
	{ok, Sess} = amqp1_connection:begin_session(Conn),
	timer:sleep(2000),
	ct:pal("Conn ~p, Sess ~p, let's attach.", [Conn, Sess]),
	GetLink = amqp1_session:get_link(Sess, GL),
	%% TODO: assert error
	timer:sleep(2000),
	ct:pal("amqp1_session:get_link(Sess, GL) =>~n1: ~120p.", [GetLink]),
	timer:sleep(2000),
	ok = amqp1_session:end_session(Sess),
	ok = amqp1_connection:stop(Conn),
	ok.

send_messssage(_Config) ->
	ok = ?TESTED:start(),
	{ok, Conn} = amqp1:connect(params_qpid()),
	{ok, Session1} = amqp1_connection:begin_session(Conn),
	ok = amqp_session:send_message(Session1),
	ok = amqp1_session:end_session(Session1),
	ok = amqp1_connection:stop(Conn),
	timer:sleep(1000),
	ok.

multiple_opened_sessions(_Config) ->
	ok = ?TESTED:start(),
	{ok, Conn} = amqp1:connect(params_qpid()),
	ct:pal("It seems that we are now connected to AMQP1 server"),
	{ok, Session1} = amqp1_connection:begin_session(Conn),
	ct:pal("It seems that we have open session 1 ~p", [Session1]),
	{ok, Session2} = amqp1_connection:begin_session(Conn),
	ct:pal("It seems that we have open session 2 ~p", [Session2]),
	ok = amqp1_session:end_session(Session1),
	ok = amqp1_session:end_session(Session2),
	ok = amqp1_connection:stop(Conn),
	timer:sleep(1000),
	ok.

start_connect_begin_end_close_stop(_Config) ->
	ok = ?TESTED:start(),
	{ok, Conn} = amqp1:connect(params_qpid()),
	ct:pal("It seems that we are now connected to AMQP1 server"),
	{ok, Session} = amqp1_connection:begin_session(Conn),
	ct:pal("It seems that we have an open session ~p", [Session]),
	ok = amqp1_session:end_session(Session),
	ok = amqp1_connection:stop(Conn),
	timer:sleep(1000),
	ok.

start_connect_begin_close_stop(_Config) ->
	ok = ?TESTED:start(),
	{ok, Conn} = amqp1:connect(params_qpid()),
	ct:pal("It seems that we are now connected to AMQP1 server"),
	{ok, Session} = amqp1_connection:begin_session(Conn),
	ct:pal("It seems that we have an open session ~p", [Session]),
	ok = amqp1_connection:stop(Conn),
	ok.

start_connect_close_stop(_Config) ->
	ok = ?TESTED:start(),
	Start = amqp1:connect(params_qpid()),
	ct:pal("Start: ~p", [Start]),
	{ok, Pid} = Start,
	timer:sleep(3*1000),
	ok = amqp1_connection:stop(Pid),
	timer:sleep(3*1000),
	ok = ?TESTED:stop(),
	ok.

start_stop_whole_skelet(_Config) ->
	ok = ?TESTED:start(),
	ok = ?TESTED:stop(),
	ok.

app_start_and_try_connect(_Config) ->
	amqp1:connect(params_qpid()),
	ok.

app_start_stop(_Config) ->
	amqp1:start(),
	amqp1:stop(),
	ok.

%% Locals %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

params_qpid_cltest() ->
	#amqp1_connection_parameters{host = "localhost",
								 virtual = "cltest",
								 port = 5672,
								 user = <<"guest">>,
								 password = <<"guest">>,
								 options = []}.

params_qpid() ->
	#amqp1_connection_parameters{host = "localhost",
								 %% virtual = "cltest",
								 virtual = "default",
								 port = 5672,
								 user = <<"guest">>,
								 password = <<"guest">>,
								 options = []}.

% end of file









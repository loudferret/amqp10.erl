
-module(amqp1_sup).

-behaviour(supervisor).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?SERVER, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	?L_DEBUG("~s:init().", [?MODULE_STRING]),
    {ok, {	{one_for_one, 5, 10},
			[connection_sup_spec(),
			 comm_sup_spec(),
			 codec_sup_spec(),
			 session_sup_spec()]
		}
   	}.

connection_sup_spec() ->
	{	amqp1_connection_sup,
		{amqp1_connection_sup, start_link, []},
		permanent,
		5000,
		supervisor,
		[amqp1_connection_sup]}.

comm_sup_spec() ->
	{	amqp1_comm_sup,
		{amqp1_comm_sup, start_link, []},
		permanent,
		5000,
		supervisor,
		[amqp1_comm_sup]}.

codec_sup_spec() ->
	{	amqp1_codec_sup,
		{amqp1_codec_sup, start_link, []},
		permanent,
		5000,
		supervisor,
		[amqp1_codec_sup]}.

session_sup_spec() ->
	{	amqp1_session_sup,
		{amqp1_session_sup, start_link, []},
		permanent,
		5000,
		supervisor,
		[amqp1_session_sup]}.





% end of file


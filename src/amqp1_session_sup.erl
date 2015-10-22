
-module(amqp1_session_sup).

-behaviour(supervisor).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

%% API
-export([start_link/0, start_session_process/3]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?SERVER, []).

start_session_process(CodecPID, Connection, Server) ->
	supervisor:start_child(?SERVER, [CodecPID, Connection, Server]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	?L_DEBUG("~s:init().", [?MODULE_STRING]),
    {ok, { {simple_one_for_one, 2, 5}, [session_process_spec()]} }.

session_process_spec() ->
	{	amqp1_session_process,
		{amqp1_session_process, start_link, []},
		temporary, %% TODO which one would be correct behaviour ??
		5000,
		worker,
		[amqp1_session_process]}.



% end of file



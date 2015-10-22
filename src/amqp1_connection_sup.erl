
-module(amqp1_connection_sup).

-behaviour(supervisor).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

%% API
-export([start_link/0]).
-export([start_connection/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?SERVER, []).

start_connection(#amqp1_connection_parameters{} = P) ->
	?L_DEBUG("~s:start_connection(P)", [?MODULE_STRING]),
	supervisor:start_child(?SERVER, [P]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	?L_DEBUG("~s:init()", [?MODULE_STRING]),
    {ok, { {simple_one_for_one, 2, 5}, [connection_spec()]} }.

connection_spec() ->
	{	amqp1_connection,
		{amqp1_connection, start_link, []},
		temporary,
		5000,
		worker,
		[amqp1_connection]}.




-module(amqp1_codec_sup).

-behaviour(supervisor).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

%% API
-export([start_link/0, start_codec/2]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?SERVER, []).

%% Common way of start
start_codec(ConnectionPID, SenderPID) ->
	supervisor:start_child(?SERVER, [ConnectionPID, SenderPID]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	?L_DEBUG("~s:init()", [?MODULE_STRING]),
    {ok, { {simple_one_for_one, 2, 5}, [codec_spec()]} }.

codec_spec() ->
	{	amqp1_codec,
		{amqp1_codec, start_link, []},
		transient,
		5000,
		worker,
		[amqp1_codec]}.



% end of file


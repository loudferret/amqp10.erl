
-module(amqp1_comm_sup).

-behaviour(supervisor).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

%% API
-export([start_link/0]).
-export([start_sender/3, start_receiver/3]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?SERVER, []).

start_sender(Socket, ConnPID, ChDB) ->
	supervisor:start_child(?SERVER, sender_spec(Socket, ConnPID, ChDB)).

start_receiver(Socket, ConnPID, ChDB) ->
	supervisor:start_child(?SERVER, receiver_spec(Socket, ConnPID, ChDB)).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	?L_DEBUG("~s:init()", [?MODULE_STRING]),
    {ok, { {one_for_all, 5, 10}, []}}.

%% TODO: permanent / transient / temporary
%%  - what's the proper behaviour when the socket goes down ?

sender_spec(Socket, ConnPID, ChDB) ->
	%%{	amqp1_sender,
	{	the_ref(amqp1_sender),
		{amqp1_sender, start_link, [Socket, ConnPID, ChDB]},
		temporary,
		5000,
		worker,
		[amqp1_sender]}.

receiver_spec(Socket, ConnPID, ChDB) ->
	%%{	amqp1_receiver,
	{	the_ref(amqp1_receiver),
		{amqp1_receiver, start_link, [Socket, ConnPID, ChDB]},
		temporary,
		5000,
		worker,
		[amqp1_receiver]}.

the_ref(Id) ->
	iolist_to_binary(io_lib:format("~p.~p",[Id,make_ref()])).

% end of file





-module(amqp1_sender).

-behavior(gen_server).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(SENDF, send_frame).
-define(SENDB, send_binary).

%% API
-export([start_link/3]).
-export([send/2]).

%% Callbacks
-export([init/1]).
-export([handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(sendst, {socket, conn, chdb}).


%% API %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link(Socket, ConnPID, ChDB) ->
        gen_server:start_link(?MODULE, {Socket, ConnPID, ChDB}, []).

%% OBSO - do not use #frame{}
send(SenderPID, #frame{} = F) ->
	gen_server:cast(SenderPID, {?SENDF, F});
send(SenderPID, B) when is_binary(B) ->
	gen_server:cast(SenderPID, {?SENDB, B}).

%% Callbacks %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init({Socket, ConnPID, ChDB}) ->
	?L_DEBUG("--> ~p ~s.init()", [self(), ?MODULE_STRING]),
	process_flag(trap_exit, true),
	true = link(Socket),
	{ok, #sendst{socket = Socket, conn = ConnPID, chdb = ChDB}}.

%% CALLS ------------------------------------------------------------

handle_call(Rq, _From, #sendst{} = State) ->
	?L_ERROR("~s:handle_call(~p) - unexpected call.", [?MODULE_STRING, Rq]),
	{stop, unexpected_call, State}.

%% CASTS ------------------------------------------------------------

handle_cast({?SENDF, #frame{} = F}, #sendst{socket = S} = State) ->
	dsend(S, amqp1_framing:frame_to_binary(F)),	%% TODO
	{noreply, State};

handle_cast({?SENDB, B}, #sendst{socket = S} = State) ->
	dsend(S, B),
	{noreply, State};

handle_cast(Rq, #sendst{} = State) ->
	?L_ERROR("~s:handle_cast(~p) - unexpected cast", [?MODULE_STRING, Rq]),
	{stop, unexpected_cast, State}.


%% INFOS ------------------------------------------------------------

%% trapping exits
handle_info({'EXIT', Port, Reason}, #sendst{} = State) when is_port(Port) ->
	?L_DEBUG("SENDER noticed fallen socket ~p:~n~p", [Port, Reason]),
	{stop, normal, State};

handle_info(Rq, #sendst{} = State) ->
	?L_ERROR("~s:handle_info(~p) - unexpected info.", [?MODULE_STRING, Rq]),
	{stop, unexpected_info, State}.

code_change(_OldVsn, #sendst{} = State, _Extra) ->
	{ok, State}.

terminate(Reason, #sendst{} = _State) ->
	?L_INFO("~s goes down: ~p.", [?MODULE_STRING, Reason]),
	ok.

%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

dsend(S, Data) ->
	%% ?L_DEBUG("Sender sends:~n-->>~120p", [Data]),
	?L_DEBUG("Sender sends ~p Bytes.", [byte_size(iolist_to_binary(Data))]),
	amqp1_net:send(S, Data).



% end of file




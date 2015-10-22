
-module(amqp1_receiver).

-behavior(gen_server).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% API
-export([start_link/3]).

%% Callbacks
-export([init/1]).
-export([handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(recvst, {socket, conn, chdb, buff = <<>>}).


%% API %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link(Socket, ConnPID, ChDB) ->
        gen_server:start_link(?MODULE, {Socket, ConnPID, ChDB}, []).

%% Callbacks %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init({Socket, ConnPID, ChDB}) ->
	?L_DEBUG("--> ~p ~s.init(~p,~p,~p)",
			 [self(), ?MODULE_STRING, Socket, ConnPID, ChDB]),
	{ok, #recvst{socket = Socket, conn = ConnPID, chdb = ChDB}}.

handle_call(_Rq, _From, #recvst{} = State) ->
	{reply, error, State}.

handle_cast(Rq, #recvst{} = State) ->
	?L_ERROR("~s:handle_cast(~p) - unexpected cast", [?MODULE_STRING, Rq]),
	{stop, unexpected_cast, State}.


%% Incoming data over TCP
handle_info({tcp, _P, InD}, #recvst{socket = S, buff = Buff, chdb = DB} = State) ->
	?L_DEBUG("~s: tcp_recv ~120p", [?MODULE_STRING, InD]),
	NBuff = case pick_frames(add_to_buffer(InD, Buff)) of
		{[], NB} ->
			NB;
		{L, NB} ->
			%% ?L_DEBUG("RECVR pass_to_decoder(~120p),~nrest ~120p", [L, NB]),
			pass_to_decoder(DB, parse_frames(L)),
			NB;
		Error ->
			?L_ERROR("~s:handle_info(tcp) ~p", [Error]),
			error("Weird data or so :-/")
	end,
	inet:setopts(S, [{active, once}]),
	{noreply, State#recvst{buff = NBuff}};

%% The Socket went down -> we need to let know all connected parties
handle_info({tcp_closed, S}, #recvst{socket = S} = State) ->
	?L_WARN("~s: socket ~p went down. Let interested know.", [?MODULE_STRING, S]),
	{stop, socket_down, State#recvst{buff = <<>>}};

handle_info(_Info, #recvst{} = State) ->
	{noreply, State}.

code_change(_OldVsn, #recvst{} = State, _Extra) ->
	{ok, State}.

terminate(Reason, #recvst{} = _State) ->
	?L_DEBUG("RECVR terminate:~p", [Reason]),
	ok.

%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

pass_to_decoder(_DB, []) ->
	ok;
pass_to_decoder(DB, [?AMQP|T]) ->	% -> Authenticated AMQP
	amqp1_codec:decode_and_pass(ets:lookup(DB, 0), ?AMQP),
	pass_to_decoder(DB, T);
pass_to_decoder(DB, [?TLS|T]) ->	% -> TLS Auth
	amqp1_codec:decode_and_pass(ets:lookup(DB, 0), ?TLS),
	pass_to_decoder(DB, T);
pass_to_decoder(DB, [?SASL|T]) ->	% -> SASL Auth
	amqp1_codec:decode_and_pass(ets:lookup(DB, 0), ?SASL),
	pass_to_decoder(DB, T);
pass_to_decoder(DB, [#frame{channel = Ch} = HF|T]) ->	% -> Common AMQP Frame
	%% ?L_DEBUG("LOOKUP(~p,~p)",[DB,Ch]),
	case ets:lookup(DB, Ch) of
		[] -> amqp1_codec:decode_and_pass(ets:lookup(DB, 0), HF);
		[ChPid] -> amqp1_codec:decode_and_pass([ChPid], HF);
		Error -> ?L_ERROR("Lookup error ~p", [Error])
	end,
	pass_to_decoder(DB, T).

parse_frames(FramesL) ->
	amqp1_framing:parse_all_frames(FramesL).

pick_frames(B) ->
	%% ?L_DEBUG(">>> PICK ~120p", [B]),
	amqp1_framing:pick_frames(B).

add_to_buffer(D, Buff) ->
	<<Buff/binary, D/binary>>.


% end of file


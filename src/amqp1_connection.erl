
-module(amqp1_connection).

-behaviour(gen_server).

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").
-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
%% FIXME:
-compile(export_all).
-endif.

%% API
-export([start/1, start_link/1, stop/1, stop_cast/1]).
-export([connect/1]).
-export([begin_session/1]).

%% Callbacks
-export([init/1]).
-export([handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% OpModes
-define(MNONE, mode_none).
-define(MAUTH, mode_auth).
-define(MOPEN, mode_open).
-define(MAMQP, mode_amqp).
-define(MCLOSE, mode_close).

-define(CONNECT, connect).
-define(BEGIN_SESSION, begin_session).

%% TODO: make configurable
-define(RECV_TMEOUT, 500).

%% mod						OpMode (?TLS/?SASL/?AMQP/?NONE/?CLOSE)
%% mod						OpMode none/auth/amqp/close
%% socket					Socket (port#)
%% sender, receiver, codec	processes
%% inchdb						in-going channel DB - ETS ID
%% outchdb						out-going channel DB - ETS ID
%% auth						= {<AuthProtocol>, <AuthHeader>, <AuthModule>}
%% params					#amqp1_connection_parameters{}
-record(connst, {mod = ?NONE, client = ?NONE,
				 socket, sender = ?NONE, receiver = ?NONE,
				 codec = ?NONE, inchdb = ?NONE, outchdb = ?NONE,
				 auth = ?NONE, params, server = #server_props{}}).

%% ===================================================================
%% API functions
%% ===================================================================

start(#amqp1_connection_parameters{} = P) ->
	amqp1_connection_sup:start_connection(P);

start([#amqp1_connection_parameters{} = P]) ->
	?L_DEBUG("amqp1_connection:start()"),
    gen_server:start(?MODULE, P, []).

start_link(#amqp1_connection_parameters{} = P) ->
	?L_DEBUG("amqp1_connection:start_link()"),
    gen_server:start_link(?MODULE, P, []).

connect(Connection) ->
	gen_server:call(Connection, ?CONNECT, connect_timeout()).

stop(Connection) ->
	?L_DEBUG("amqp1_connection:stop(~p)", [Connection]),
	gen_server:call(Connection, fin).

stop_cast(Connection) ->
	?L_DEBUG("amqp1_connection:stop_cast(~p)", [Connection]),
	gen_server:cast(Connection, fin).

%% TODO: ????  begin_session(Connection, Parameters) ???? 
begin_session(Connection) ->
	?L_DEBUG("amqp1_connection:begin_session(~p)", [Connection]),
	gen_server:call(Connection, ?BEGIN_SESSION, begin_timeout()).


%% ===================================================================
%% Callbacks
%% ===================================================================

%% 3. postponed connect()
init(#amqp1_connection_parameters{} = Params) ->
	?L_DEBUG("--> ~120p ~s:init(~120p)", [self(), ?MODULE_STRING, Params]),
	process_flag(trap_exit, true),
	{InChDB, OutChDB} = new_channel_dbs(),
	{ok, #connst{params = Params, inchdb = InChDB, outchdb = OutChDB}};
%% 2. repeatable do_connect()
init(#amqp1_connection_parameters{} = Params) ->
	?L_DEBUG("--> ~120p ~s:init(~120p)", [self(), ?MODULE_STRING, Params]),
	process_flag(trap_exit, true),
	do_connect(Params).


%% CASTS ------------------------------------------------------------

handle_cast({?DECODED, ?AMQP},
		#connst{codec = {Codec, _}, sender = {Sender, _}} = State) ->
	?L_DEBUG("A: ~s:handle_cast({DECODED, amqp})", [?MODULE_STRING]),
	amqp1_sender:send(Sender, ?AMQP1_HEADER),
	amqp1_codec:encode_and_pass(Codec, 0, amqp1_open(State)),
	{noreply, State#connst{mod = ?MOPEN}};

handle_cast({?DECODED, ?SASL}, #connst{mod = ?MAUTH} = State) ->
	?L_DEBUG(" B: ~s:handle_cast({DECODED, sasl})", [?MODULE_STRING]),
	%{noreply, State#connst{}};
	% TODO: What? received <<"AMQP", 3, 1, 0, 0>> and now?
	%		-> SASL Challenge is gonna arrive soon. just wait
	{noreply, State};

handle_cast({?DECODED, ?TLS}, #connst{mod = ?MAUTH} = State) ->
	?L_DEBUG("C: ~s:handle_cast({DECODED, tls})", [?MODULE_STRING]),
	%% TODO: TLS Challenge arrives? Not implemented yet.
	{noreply, State#connst{}};

handle_cast({?DECODED, #frame{body = [#'v1_0.open'{} = Open]}},
		   	#connst{mod = ?MOPEN, client = C} = State) ->
	%% open{} sent already, received is a confirmation from server
	NState = handle_open(Open, State),
	gen_server:reply(C, ok),
	{noreply, NState#connst{mod = ?MAMQP, client = ?NONE}};

handle_cast({?DECODED, #frame{body = [#'v1_0.close'{error = E}]}},
		   	#connst{mod = ?MAMQP} = State) ->
	?L_INFO("AMQP1 Close received from server: ~p.", [E]),
	{noreply, State#connst{mod = ?MCLOSE}};

handle_cast({?DECODED, #frame{body = [#'v1_0.close'{error = E}]}},
		   	#connst{mod = ?MCLOSE} = State) ->
	?L_INFO("AMQP1 Close confirmed from server (E: ~p).", [E]),
	%% TODO: ?? Send amqp1_close{} ?? Socket goes down though.
	{noreply, State};

handle_cast({?DECODED, #frame{channel = LCh,
							  body = [#'v1_0.begin'{remote_channel = undefined}]}},
		#connst{mod = ?MAMQP, outchdb = _OutChDB} = State) ->
	?L_DEBUG("CONN(AMQP) ~p -> #'v1_0.begin'{undefCh} new session for server", [LCh]),
	%% TODO finish -> undefined == new incomnig #begin{} from server
	{noreply, State};

handle_cast(
		{?DECODED, #frame{channel=LCh, body=[#'v1_0.begin'{remote_channel=RCh}]} = F},
		#connst{mod = ?MAMQP, inchdb = InChDB, outchdb = OutChDB} = State) ->
	?L_DEBUG("CONN(AMQP) ~p -> #'v1_0.begin'{~p}", [LCh, RCh]),
	%% Find out RCh in outchdb,
	case ets:lookup(OutChDB, ?VALUE(RCh)) of
		[{_Ch, Session, Codec, From}] ->
			?L_DEBUG("CONN begins SESS and replies to orig client ~120p.",[From]),
			%% pass to a proper session & reply
			%% TODO: should not be replyed from the session process ?
			amqp1_session:begin_session(Session, F),
			gen_server:reply(From, {ok, Session}),
			%% record LCh to inchdb, - does not need to be _NEW_
			%% true = ets:insert_new(InChDB, {LCh, Session});
			true = ets:insert(InChDB, {LCh, Codec});
		E ->
			?L_DEBUG("CONN got into trouble with begin: ~p", [E])
	end,
	{noreply, State};
	
handle_cast({?DECODED, #frame{body = [#'v1_0.end'{}]}},
		   	#connst{mod = ?MAMQP} = State) ->
	?L_DEBUG("CONN(AMQP) #'v1_0.end'{}"),
	{noreply, State};
	
handle_cast({?DECODED, #frame{body = [#'v1_0.end'{}]}},
		   	#connst{mod = M} = State) ->
	?L_DEBUG("=== CONN(AMQP) #'v1_0.end'{} in mode ~p", [M]),
	{noreply, State};
	
handle_cast({?DECODED, #frame{body = FB}}, #connst{codec = {Codec,_},
				 mod = ?MAUTH, auth = {?SASL,H,Mod}, params = Par} = State) ->
%%	?L_DEBUG("D: ~s:handle_cast(DECODED,~n~120p ).", [?MODULE_STRING, F]),
%% 	?L_DEBUG("D: ~s:handle_cast({DECODED, DAT}) -> ~120p", [?MODULE_STRING, AuthM]),
	%% TODO finish/handle
	NS = case Mod:auth(FB, Par) of
		{NAuthMod, Resp} ->
			amqp1_codec:encode_and_pass(Codec, ?FT_SASL, 0, Resp),
			State#connst{auth = {?SASL, H, NAuthMod}};
		ok ->
			State;
		error ->
			%% Try another auth mechanism
			%% -> amqp1_auth:supported(State#connst.auth.1) == ?SASL
			%% ?? do_connect(State#connst{mod = ?MNONE})
			do_connect(State)
	end,
	{noreply, NS};

handle_cast(fin, #connst{} = State) ->
	?L_DEBUG("amqp_connection:stop_cast()"),
	NState = fin(State),
	%% {stop, normal, State};
	{noreply, NState};

handle_cast(Rq, #connst{mod = M} = State) ->
	?L_ERROR("~s:handle_cast(~p,~p) - unexpected cast.", [?MODULE_STRING,Rq,M]),
	{stop, unexpected_cast, State}.

%% CALLS ------------------------------------------------------------

handle_call(?CONNECT, From, #connst{mod = ?NONE, client = ?NONE} = State) ->
	?L_DEBUG("CONN CONNECT from ~p.", [From]),
	case do_connect(State#connst{client = From}) of
		error ->
		   	{stop, normal, {error, not_authenticated}, State};
		{ok, NState} ->
		   	{noreply, NState}
	end;

%% noreply -> need to reply in-time
handle_call(?BEGIN_SESSION, From, #connst{mod = ?MAMQP} = State) ->
	?L_DEBUG("CONN begin_session from ~p.", [From]),
	{ok, ChNo, _Session, _Codec} = begin_codec_and_session(From, State),
	%% v1.0_begin sent,
	%% incoming must be paired - using channel No. - with the session and From
	%% -> -> -> gen_server:reply(Session)
	?L_DEBUG("CONN new session Ch#~p -> ~p (call -> noreply)", [ChNo, session]),
	{noreply, State};

handle_call(?BEGIN_SESSION, From, #connst{mod = M} = State) ->
	?L_DEBUG("CONN[~p] begin_session from ~p. Not connected.", [M, From]),
	{reply, {error, not_connected}, State};

handle_call(fin, From, #connst{} = State) ->
	?L_DEBUG("Got fin from ~p.", [From]),
	NState = fin(State),
	%% {stop, normal, ok, State};
	%% TODO: We need to postpone reply !!!!!!
	{reply, ok, NState};

handle_call(Rq, _From, #connst{} = State) ->
	?L_ERROR("~s:handle_call(~p) - unexpected call.", [?MODULE_STRING, Rq]),
	{stop, unexpected_call, State}.


%% INFOS ------------------------------------------------------------

%% trapping exitrs
handle_info({'EXIT', From,  Reason}, #connst{} = State) ->
	?L_DEBUG("EXIT from ~p:~n~p.", [From, Reason]),
	{noreply, State};

%% receiver down
handle_info({'DOWN', Ref, _T, _P, socket_down},
		#connst{mod = ?MAUTH, receiver = {_P, Ref}} = State) ->
	?L_DEBUG("~s: RECVR went down - closed Socket, failed AUTH.",[?MODULE_STRING]),
	%% TODO: socket is down, not much to do than try another Auth method
	%% {noreply, State#connst{receiver = ?NONE}};
	%% {stop, normal, State};
	{ok, NState} = do_connect(State),
	{noreply, NState};

handle_info({'DOWN', Ref, _T, _P, socket_down},
		#connst{mod = ?MCLOSE, receiver = {_P, Ref}} = State) ->
	?L_DEBUG("~s: RECEIVER went down due to #close{}.", [?MODULE_STRING]),
	%% {noreply, State#connst{mod = ?MNONE}}; - did I receive v1.0_close ?
	{noreply, State};

handle_info({'DOWN', Ref, _T, _P, socket_down},
		#connst{mod = M, receiver = {_P, Ref}} = State) ->
	?L_DEBUG("~s[~p]: RECEIVER went down due to closed Socket.",[?MODULE_STRING,M]),
	%% TODO: what mode to restart Auth? or {stop, normal, State} ?
	{ok, NState} = do_connect(State),
	{noreply, NState};
	%%	{noreply, State#connst{receiver = ?NONE}};

%% sender down
handle_info({'DOWN', Ref, _T, _P, Info}, #connst{sender = {_P, Ref}} = State) ->
	?L_DEBUG("~s: SENDER went down: ~p.",  [?MODULE_STRING, Info]),
	{noreply, State#connst{sender = ?NONE}};

%% codec down
handle_info({'DOWN', Ref, _T, _P, Info}, #connst{codec = {_P, Ref}} = State) ->
	?L_DEBUG("~s: CODEC went down: ~p.",  [?MODULE_STRING, Info]),
	{noreply, State#connst{codec = ?NONE}};

handle_info({'DOWN', Ref, _T, Pid, Info}, #connst{} = State) ->
	?L_DEBUG(" An old process died: P.~p, R.~p, I.~p.", [Pid, Ref, Info]),
	{noreply, State};

handle_info(Rq, #connst{} = State) ->
	?L_ERROR("~s:handle_info(~p) - unexpected info.", [?MODULE_STRING, Rq]),
	{stop, unexpected_info, State}.


code_change(_OldVsn, #connst{} = State, _Extra) ->
	{ok, State}.

terminate(Reason, #connst{} = State) ->
	?L_INFO("------ CONN ~p is terminating ------~n~p", [self(), Reason]),
	%% TODO: terminate sessions ?
	fin_to_sessions_and_codecs(State#connst.outchdb),
	ok.

%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

begin_codec_and_session(From, 
		#connst{outchdb = OutChDB, sender = {Sender, _}, server = Server} = _State) ->
	?L_DEBUG("CONN begin_codec_and_session()"),
	{ok, Codec} = amqp1_codec_sup:start_codec(self(), Sender),
	{ok, Session} = amqp1_session_sup:start_session_process(Codec, self(), Server),
	%% 1. get out-channel for session - this is not a transaction, though
	Last = case ets:last(OutChDB) of '$end_of_table' -> 0; V -> V end,
	ChNo = Last + 1,
	true = ets:insert_new(OutChDB, {ChNo, Session, Codec, From}),
	%% 2. TODO: need to check if LastChNo <= MaxChNo
	%% 3. let session do #begin{}
	ok = amqp1_session:begin_session(Session, ChNo),
	%% TODO: should i monitor session(s) ?
	{ok, ChNo, Session, Codec}.

do_connect(#amqp1_connection_parameters{} = P) -> do_connect(#connst{params = P});
do_connect(#connst{inchdb = ChDB, params = Params} = State) ->
	?L_DEBUG(">----- auth 4 do_connect(~p) --------<", [State#connst.auth]),
	Socket = tcp_connect(dig_conn_params(Params)),
	{ok, Sender, Receiver, MyCodec} = start_essentials(Socket, ChDB),
	true = ets:insert(ChDB, {0, MyCodec}),
	inet:setopts(Socket, [{active, once}]),
	ok = amqp1_net:controlling(Socket, Receiver),
	%% FIXME: this can return undefined
	AUTHMOD = case ?ERST(State#connst.auth) of
				?NONE -> amqp1_auth:supported(first);
				AP -> amqp1_auth:supported(AP)
			end,
	case AUTHMOD of
		undefined -> %% End
			?L_DEBUG("amqp1_auth:supported() returned 'undefined'"),
			error;
		{AuthP, AuthHD} ->
			?L_DEBUG("amqp1_auth:supported() returned ~p.",[AUTHMOD]),
			amqp1_sender:send(Sender, AuthHD),
			{ok, AuthMod} = amqp1_auth:get_auth_module(AuthP),
			{ok, State#connst{mod = ?MAUTH,
						socket = Socket,
						sender = {Sender, monitor(process, Sender)},
						receiver = {Receiver, monitor(process, Receiver)},
						codec = {MyCodec, monitor(process, MyCodec)},
						auth = {AuthP, AuthHD, AuthMod}}}
	end.


%% #'v1_0.open'{string mandatory container_id,
%%				string hostname,		TODO: server's
%%				uint max_frame_size,
%%				uint channel_max,
%%				milliseconds idle_time_out,
%%				ietf-language-tag multiple outgoing_locales,
%%				ietf-language-tag multiple incoming_locales,
%%				symbol multiple offered_capabilities,
%%				symbol multiple desired_capabilities,
%%				fields properties}).
handle_open(Open, #connst{} = State) ->
	?L_DEBUG("open{}: ~120p.", [Open]),
	State#connst{server = parse_open(Open)}.

parse_open(#'v1_0.open'{} = Open) ->
	#server_props{
		id = ?VALUE(Open#'v1_0.open'.container_id),
		hostname = ?VALUE(Open#'v1_0.open'.hostname),
		max_frame_size = ?VALUE(Open#'v1_0.open'.max_frame_size),
		channel_max = ?VALUE(Open#'v1_0.open'.channel_max),
		idle_time_out = ?VALUE(Open#'v1_0.open'.idle_time_out),
		offered = ?VALUE(Open#'v1_0.open'.offered_capabilities),
		desired = ?VALUE(Open#'v1_0.open'.desired_capabilities),
		outgoing_locales = case ?VALUE(Open#'v1_0.open'.outgoing_locales) of
								undefined -> ?DEFLOC;
								L -> L
							end,
		incoming_locales = case ?VALUE(Open#'v1_0.open'.incoming_locales) of
								undefined -> ?DEFLOC;
								L -> L
							end
	 }.

start_essentials(Socket, DB) ->
	{ok, Sender} = amqp1_comm_sup:start_sender(Socket, self(), DB),
	{ok, Receiver} = amqp1_comm_sup:start_receiver(Socket, self(), DB),
	{ok, Codec} = amqp1_codec_sup:start_codec(self(), Sender),
	{ok, Sender, Receiver, Codec}.

%% {InChDB, OutChDB}
new_channel_dbs() ->
	{
		ets:new(channels,
		   	[set, public,
			 {read_concurrency, true}, {write_concurrency, true}]),
		ets:new(channels,
		   	[ordered_set, protected,
			 {read_concurrency, true}, {write_concurrency, true}])
	}.
%		   	[set, protected, {read_concurrency, true}, {write_concurrency, true}]).

tcp_connect({Host, Port, Options}) ->
	{ok, Socket} = amqp1_net:connect(Host, Port, tcp_options(Options)),
	Socket.

tcp_options(Opts) ->
	Opts ++ ?TCP_CONNECT_OPTIONS.

dig_conn_params(#amqp1_connection_parameters{host = H, port = P, options = O}) ->
	{H, P, O}.

fin(#connst{socket = _S, codec = {C, _M}} = State) ->
	%% 1. #'v1_0.close'{}
	amqp1_codec:encode_and_pass(C, 0, amqp1_close()),
	%% 2. close socket - %% Who???
	State#connst{mod = ?MCLOSE}.


%% #'v1_0.open'{string mandatory container_id,
%%				string hostname, - the VirtualHost !!
%%				uint max_frame_size,
%%				uint channel_max,
%%				milliseconds idle_time_out,
%%				ietf-language-tag multiple outgoing_locales,
%%				ietf-language-tag multiple incoming_locales,
%%				symbol multiple offered_capabilities,
%%				symbol multiple desired_capabilities,
%%				fields properties}).
amqp1_open(#connst{params = P}) ->
	{ok, SHN} = inet:gethostname(),
	LN = iolist_to_binary(SHN),
	HN = servers_hostname(P),
	#'v1_0.open'{	container_id = {utf8, <<"CID-", LN/binary>>}
					, hostname = {utf8, HN}
					, channel_max = {uint, 1024}
	}.

servers_hostname(#amqp1_connection_parameters{host = H, virtual = VH}) ->
	%% iolist_to_binary(H ++ "/" ++ VH).
	iolist_to_binary(VH).

amqp1_close() -> amqp1_close(undefined).
amqp1_close(E) -> #'v1_0.close'{error = E}.

%% TODO: need to be configurable (connection_timeout)
connect_timeout() -> 10*1000.

%% TODO: need to be configurable (begin_timeout)
begin_timeout() -> 5 * 1000.

fin_to_sessions_and_codecs(DB) ->
	%% {ChNo, Session, Codec, From}
	First = ets:first(DB),
	fin_to_sessions_and_codecs(DB, First).

fin_to_sessions_and_codecs(_DB, '$end_of_table') -> ok;
fin_to_sessions_and_codecs(DB, Key) ->
	[{_Ch, S, C, _F}] = ets:lookup(DB, Key),
	gen_server:cast(fin, S),
	gen_server:cast(fin, C),
	Next = ets:next(DB, Key),
	fin_to_sessions_and_codecs(DB, Next).


%% TEST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-ifdef(TEST).

amqp1_open_test() ->
	P = #amqp1_connection_parameters{host = "localhost.honeywell.com"},
	O = amqp1_open(#connst{params = P}),
	amqp1_framing:record_to_binary(O),
	ok.

amqp1_close_test() ->
	amqp1_framing:record_to_binary(amqp1_close()),
	amqp1_framing:record_to_binary(amqp1_close({binary, <<"Error_so_I_close.">>})),
	ok.

-endif.


%% end of file



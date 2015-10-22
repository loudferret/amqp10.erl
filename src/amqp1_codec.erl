
-module(amqp1_codec).

-behavior(gen_server).

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").
-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% API
-export([start_link/2]).
-export([the_session/2]).
-export([encode_and_pass/3, encode_and_pass/4, decode_and_pass/2]).

%% Callbacks
-export([init/1]).
-export([handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(codecst, {connection, sender, sendermon, session}).

-define(THESESSION, the_session).
-define(ENCPASS, encode_and_pass_data).
-define(DECPASS, decode_and_pass_data).
-define(PASSDEC, pass_decoded_data).

%% API %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link(ConnectionPID, SenderPID)  ->
	gen_server:start_link(?MODULE, {ConnectionPID, SenderPID}, []).

the_session(CodecPID, SessionPID) ->
	gen_server:call(CodecPID, {?THESESSION, SessionPID}).

%% Incoming records
encode_and_pass(CodecPID, OutChannelNo, FrameBody) ->
	encode_and_pass(CodecPID, ?DEF_FT, OutChannelNo, FrameBody).

encode_and_pass(CodecPID, FrameType, OutChannelNo, FrameBody) ->
	gen_server:cast(CodecPID, {?ENCPASS, FrameType, OutChannelNo, FrameBody}).

%% Incoming binaries
decode_and_pass([{_Ch, CodecPID}], #frame{} = F) ->
	gen_server:cast(CodecPID, {?DECPASS, F});
decode_and_pass([{_Ch, CodecPID}], P)
						when P =:= ?AMQP orelse P =:= ?SASL orelse P =:= ?TLS ->
	gen_server:cast(CodecPID, {?PASSDEC, P}).

%% Callbacks %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init({ConnectionPID, SenderPID}) ->
	?L_DEBUG("CODEC.init(Conn.~p, Sender.~p)", [SenderPID, ConnectionPID]),
	{ok, #codecst{	connection = ConnectionPID,
					sender = SenderPID,
					sendermon = monitor(process, SenderPID),
					session = ConnectionPID}}.


%% CASTS ------------------------------------------------------------

%% Pass already decoded
handle_cast({?PASSDEC, F}, #codecst{} = State) ->
	?L_DEBUG("~s:handle_cast({PASSDEC,~p})", [?MODULE_STRING, F]),
	pass_decoded(State, F),
	{noreply, State};

%% Decode and pass
handle_cast({?DECPASS, #frame{body = B} = F}, #codecst{} = State) ->
	%% ?L_DEBUG("~s:handle_cast({DECPASS,~p}) -> ~p", [?MODULE_STRING, F, Session]),
	?L_DEBUG("CODEC handle_cast({DECPASS, #frame{}})"),
	%?L_DEBUG("~s:handle_cast({DECPASS, ~p}) -> ~p", [?MODULE_STRING, F, Session]),
	pass_decoded(State, decide_form(F, amqp1_framing:binary_to_records(B))),
	{noreply, State};

handle_cast({?ENCPASS, FT, Ch, FB}, #codecst{sender = Sender} = State) ->
	?L_DEBUG("~s:handle_cast({ENCPASS,~120p,~120p})", [?MODULE_STRING, FB, Ch]),
	%% build #frame{type = ?, channel = ChNo, body = enc(F)}
	pass_encoded(Sender, #frame{type = FT, channel = Ch, body = encode_data(FB)}),
	{noreply, State};

handle_cast(fin, #codecst{} = State) ->
	{stop, normal, State};

handle_cast(Rq, #codecst{} = State) ->
	?L_ERROR("~s:handle_cast(~p) - unexpected cast", [?MODULE_STRING, Rq]),
	{stop, unexpected_cast, State}.

%% CALLS ------------------------------------------------------------

handle_call({?THESESSION, SessionPID}, _From,
			#codecst{connection = CPID, session = CPID} = State) ->
	?L_DEBUG("CODEC got its own session_process ~p.", [SessionPID]),
	{reply, ok, State#codecst{session = SessionPID}};

handle_call({?THESESSION, SPID}, _From, #codecst{session = OSPID} = State) ->
	?L_DEBUG("CODEC got another session_process ~p instead of ~p.", [SPID, OSPID]),
	{stop, unexpected_call, State};

handle_call(Rq, _From, #codecst{} = State) ->
	?L_ERROR("~s:handle_call(~p) - unexpected call.", [?MODULE_STRING, Rq]),
	{stop, unexpected_call, State}.

%% INFOS ------------------------------------------------------------

handle_info({'DOWN', Ref, _T, _P, normal}, #codecst{sendermon = Ref} = State) ->
	?L_DEBUG("CODEC: SENDER went down normally."),
	%% TODO: should I go as well?
	{stop, normal, State};

handle_info({'DOWN', Ref, _T, _P, Info}, #codecst{sendermon = Ref} = State) ->
	?L_WARN("~s:info SENDER went down ~p.", [?MODULE_STRING, Info]),
	%% TODO: should I go as well?
	{stop, normal, State};

handle_info(Rq, #codecst{} = State) ->
	?L_ERROR("~s:handle_info(~p) - unexpected info.", [?MODULE_STRING, Rq]),
	{stop, unexpected_info, State}.


code_change(_OldVsn, #codecst{} = State, _Extra) ->
	{ok, State}.

terminate(Reason, #codecst{sendermon = SM} = _State) ->
	?L_DEBUG("CODEC terminates: ~p", [Reason]),
	erlang:demonitor(SM),
	%% TODO: ??
	ok.

%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

decide_form(_F, ?AMQP) -> ?AMQP;
decide_form(_F, ?SASL) -> ?SASL;
decide_form(_F, ?TLS) -> ?TLS;
decide_form(Frame, Body) -> Frame#frame{body = Body}.


%%build_frame(T, ChNo, B) ->
%%	#frame{type = T, channel = ChNo, body = B}.

encode_data(FB) ->
	amqp1_framing:record_to_binary(FB).

pass_decoded(#codecst{} = State, #frame{body = [#'v1_0.open'{}]} = F) ->
	pass_decoded(State#codecst.connection, F);
pass_decoded(#codecst{} = State, #frame{body = [#'v1_0.close'{}]} = F) ->
	pass_decoded(State#codecst.connection, F);
pass_decoded(#codecst{} = State, #frame{body = [#'v1_0.begin'{}]} = F) ->
	pass_decoded(State#codecst.connection, F);
pass_decoded(#codecst{} = State, #frame{body = [#'v1_0.end'{}]} = F) ->
	pass_decoded(State#codecst.connection, F);
pass_decoded(#codecst{} = State, F) ->
	pass_decoded(State#codecst.session, F);

pass_decoded(Pid, F) when is_pid(Pid) ->
	?L_DEBUG(">>> ~s:pass_decoded(~120p,~n~120p)", [?MODULE_STRING, Pid, F]),
	gen_server:cast(Pid, {?DECODED, F}).

pass_encoded(Sender, D) ->
	amqp1_sender:send(Sender, D).

% end of file


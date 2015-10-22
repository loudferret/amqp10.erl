
-module(amqp1_session_process).

-behavior(gen_server).

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").
-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% API
-export([start_link/3, start/3]).
-export([cast/2, call/2]).

%% Callbacks
-export([init/1, terminate/2]).
-export([handle_call/3, handle_cast/2, handle_info/2, code_change/3]).

% OpModes
-define(MNONE,    mode_none).
-define(MUNMAP,   mode_unmapped).
-define(MBEGIN,   mode_begin).
-define(MMAP,     mode_mapped).
-define(MEND,     mode_end).
%-define(M, mode_).

-define(BEGIN_SESSION, begin_session).
-define(END_SESSION, end_session).

-define(K_ATTACH, key_attach).
-define(K_ATTACH_ERR, key_attach_error).

%% links		- internal use, RemoteHandle -> #link{}
%% the_links	- API Clients LinkID, {Role, Node} -> #the_link{..., remote_handle}
-record(sessst, {mod = ?MNONE, codec = ?NONE, connection = ?NONE,
				 handle = 0, outch, inch, nextin = 0, nextout = 0,
				 session, callers, server, the_links, links}).


-record(session, {in_ch, next_in_id, next_out_id, in_win, out_win,
				  handle_max, props}).

%-record(attach, {name, handle, role, snd_settle, rcv_settle, src, tgt,
%				 unsettled,	incomplete_unsettled,
%				 initial_delivery_count, max_msg_size, props}).

-record(link, {name,
			   local_handle, remote_handle, local_role, remote_role, src, tgt,
			   delivery_count = 0, credit, available, drain, 
			   unsettled = []}).

%% to be in state of the session/link/?
%% remote-channel			= in_ch			session
%% local-channel			= out_ch		session
%% next-incoming-id			= next_in_id
%% next-outgoing-id			= next_out_id
%% incoming-window			= in_win
%% outgoing-window			= out_win
%% remote-incoming-window	= rem_in_win
%% remote-outgoing-window	= rem_out_win
%%
%% Flow Control:
%% delivery-count
%% link-credit = 0
%% available = 0
%% drain = false
%%

%% API %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% FIXME: there's no way how to create remotely opened session -
%%			the channel would be already specified by server
start(CodecPID, Connection, ServerProps) ->
	gen_server:start(?MODULE, {CodecPID, Connection, ServerProps}, []).

start_link(CodecPID, Connection, ServerProps) ->
	gen_server:start_link(?MODULE, {CodecPID, Connection, ServerProps}, []).

cast(Session, Request) ->
	gen_server:cast(Session, Request).

call(Session, Request) ->
	gen_server:call(Session, Request).

%% Callbacks %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init({Codec, Connection, ServerProps}) ->
	?L_DEBUG("~s.init()", [?MODULE_STRING]),
	ok = amqp1_codec:the_session(Codec, self()), %% sync
	{ok, #sessst{mod = ?MUNMAP,
				codec = {Codec, monitor(process, Codec)},
				connection = Connection, callers = dict:new(),
				the_links = dict:new(), links = dict:new(),
			   	server = ServerProps}}.

%% CASTS ------------------------------------------------------------

handle_cast({?BEGIN_SESSION, #frame{} = F}, #sessst{} = State) ->
	?L_DEBUG("SESS incoming cast~nbegin_session(~120p)", [F]),
	%% TODO: ???
	{noreply, State#sessst{mod = ?MMAP, inch = F#frame.channel,
						   session = parse_begin(F#frame.body)}};


handle_cast({?DECODED, #frame{body = [#'v1_0.attach'{} = F]}}, #sessst{} = State) ->
	?L_DEBUG("SESS Server attaches a link ~n~140p", [F]),
	K = {?K_ATTACH, ?VALUE(F#'v1_0.attach'.name)},
	NState = handle_attach(find_caller(K, State), F, State), %% put in {noreply,..}
	{noreply, NState};

%% {'v1_0.detach',
%%		handle = {uint,0},
%%		closed = true,
%%		error = {'v1_0.error',{symbol,<<"amqp:not-found">>},undefined,undefined}}
handle_cast({?DECODED, #frame{body = [#'v1_0.detach'{} = F]}}, #sessst{} = State) ->
	?L_DEBUG("SESS Server detaches a link ~n~140p", [F]),
	NState = handle_detach(F#'v1_0.detach'.error, F, State),
	{noreply, NState};

handle_cast({?DECODED, #frame{body = [#'v1_0.flow'{} = Flow]}}, #sessst{} = State) ->
	?L_DEBUG("SESS Incoming Flow ~140p.", [Flow]),
	NState = handle_flow(Flow, State),
	{noreply, NState};

%% incoming from Codec
handle_cast({?DECODED, F}, #sessst{} = State) ->
	?L_DEBUG("SESS cast decoded(~120p)", [F]),
	{noreply, State};

%% nice and polite
handle_cast(fin, #sessst{} = State) ->
	{stop, normal, State};

handle_cast(Rq, #sessst{} = State) ->
	?L_ERROR("~s:handle_cast(~p) - unexpected cast.", [?MODULE_STRING, Rq]),
	{stop, unexpected_cast, State}.

%% CALLS ------------------------------------------------------------

handle_call({?BEGIN_SESSION, ChNo}, _From,
			#sessst{mod = ?MUNMAP, codec = {Codec, _M}} = State) ->
	?L_DEBUG("SESS calls #begin{ch = ~p}", [ChNo]),
	amqp1_codec:encode_and_pass(Codec, ChNo, amqp1_begin(State)),
	%% can reply -> handled&replied by connection process
	{reply, ok, State#sessst{mod = ?MBEGIN, outch = ChNo}};

handle_call(?END_SESSION, _From,
			#sessst{codec = {Codec, _M}, outch = ChNo} = State) ->
	?L_DEBUG("SESS is ending."),
	%% TODO: detach links
	%% detach_links(State),
	%% TODO: #'v1_0.end{error} - should be sent in terminate/2
	amqp1_codec:encode_and_pass(Codec, ChNo, amqp1_end()),
	%% {stop, normal, ok, State#sessst{mod = ?MEND}};
	{reply, ok, State#sessst{mod = ?MEND}};

% find out an incoming/outgoing #the_link{} or create a new one
handle_call(#get_link{role = Role, node = Node} = GL, From, #sessst{} = State) ->
	?L_DEBUG("SESS Request for in/outgoing link from/to ~p/~p.", [Node, Role]),
	handle_get_link(find_the_link(Role, Node, State), GL, From, State);

%% TODO: is this even real ??
handle_call(#'v1_0.flow'{}, _From, #sessst{} = State) ->
	%% TODO: NState = handle_flow(F, State),
	%% TODO: store From
	{noreply, State};

handle_call(#'v1_0.transfer'{} = F, _From, #sessst{} = State) ->
	NState = handle_transfer(F, State),
	%% TODO: store From
	{noreply, NState};

%% TODO: is this even real ??
handle_call(#'v1_0.disposition'{} = F, _From, #sessst{} = State) ->
	NState = handle_disposition(F, State),
	%% TODO: store From
	{noreply, NState};


handle_call(#'v1_0.detach'{error = E} = F, _From, #sessst{} = State) ->
	NState = handle_detach(E, F, State), %% FIXME ???
	%% TODO: store From
	{noreply, NState};

handle_call(Rq, _From, #sessst{} = State) ->
	?L_ERROR("~s:handle_call(~p) - unexpected call.", [?MODULE_STRING, Rq]),
	{stop, unexpected_call, State}.


%% INFOS ------------------------------------------------------------

handle_info({'DOWN', Ref, _T, _P, Info}, #sessst{codec = {_P, Ref}} = State) ->
	?L_DEBUG("~s: CODEC went down: ~p.",  [?MODULE_STRING, Info]),
	%% TODO: ???
	{stop, normal, State};

handle_info(Rq, #sessst{} = State) ->
	?L_ERROR("~s:handle_info(~p) - unexpected info.", [?MODULE_STRING, Rq]),
	{stop, unexpected_info, State}.


code_change(_OldVsn, #sessst{} = State, _Extra) ->
	{ok, State}.

terminate(Reason, #sessst{codec = {_C, CM}} = _State) ->
	?L_DEBUG("SESSION terminates: ~p.", [Reason]),
	erlang:demonitor(CM),
	%% TODO: ??
	ok.

%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Link is in process of attach - currently an error, innit?
handle_get_link({ok, #the_link{remote_handle = ?NONE}}, _GL, _F, State) ->
	?L_DEBUG("SESS the_link is not attached yet - ERROR.~n~140p",
			 [dict:fetch_keys(State#sessst.the_links)]),
	error;
% The Link already exists
handle_get_link({ok, #the_link{} = TheLink}, _GL, _F, State) ->
	?L_DEBUG("SESS the_link exists, replying ~p.", [TheLink]),
	{reply, {ok, TheLink}, State}; 
% Do attach new outgoing link
handle_get_link(error, #get_link{role = Role, node = Node}, From,
	#sessst{codec = {Codec, _M}, outch = ChNo, handle = H} = State) ->
	?L_DEBUG("SESS client needs new outgoing Link -> ~p.", [Node]),
	Nam = <<"Erste Link">>,		%% FIXME
	Tgt = amqp1_target(Node),
	Att = amqp1_attach(Nam, H),
	Out = Att#'v1_0.attach'{ role = Role,
							% source = amqp1_source(Name),
							target = Tgt},
	amqp1_codec:encode_and_pass(Codec, ChNo, Out),
	% #the_link{} for clients (remote_handle yet unknown)
	TheLink = #the_link{session = self(), role = Role, name = Nam},
	% tuple for identifying client to send reply
	Caller = {From, Out},
	% #link{} for process
	{noreply,
		State#sessst{handle = inc(H),
			 the_links = store_the_link(Role, Node, TheLink, State),
			 callers = store_caller({?K_ATTACH, Nam}, Caller, State)}}.

%% from server - ROLE_SENDER
%% ----> NState = handle_attach(find_caller(K, State), F, State),
%% FIXME
handle_attach(error, F, _State) ->
	?L_DEBUG("SESS could not find caller for request ~p.", [F]),
	error;
handle_attach({ok, {From, AttOut}},
				#'v1_0.attach'{role = Role} = AttIn, #sessst{} = State) ->
	RemHandle = ?VALUE(AttIn#'v1_0.attach'.handle),
	LocHandle = ?VALUE(AttOut#'v1_0.attach'.handle),
	case get_node_from_attach(AttIn) of
		error ->
			%% no src/tgt in returned #v1attach{} -> error
			?L_WARN("SESS returned attached w/o src/tgt. ~p.", [error]),
			%% reply to caller with error, error arrives later...
			%% gen_server:reply(From, {error, not_found}),
			Node = get_node_from_attach(AttOut),
			% 1 store {key_attach_error, rem_handle}
			%				-> {From, Node, Role, ...} -> callers
			Caller = {From, AttOut},
			CKey = {?K_ATTACH_ERR, RemHandle},
			NCallers1 = store_caller(CKey, Caller, State),
			% 2 remove old record from callers
			NCallers2 = delete_caller({?K_ATTACH, Node}, NCallers1),
			% 3 remove obsolete #the_link from the_links ??
			NTheLinks = delete_the_link(not Role, Node, State),
			% 4 wait for dettach
			% 5 response accordingly
			State#sessst{the_links = NTheLinks, callers = NCallers2};
		Node ->
			%% 1. find request in the_links {Role, Node} -> #the_link{}
			%% 2. update the_links with remote_handle
			%% FIXME: returns error -> we need the other role: from our point of view
			%% TODO: we might not have the record => error
			case find_the_link(not Role, Node, State) of
				{ok, OldTheLink} ->
					?L_DEBUG("SESS OldTheLink = ~p.", [OldTheLink]),
					TheLink = OldTheLink#the_link{remote_handle = RemHandle},
					%% 3. send a reply to <From>
					gen_server:reply(From, {ok, TheLink}),
					%% 4. Store new #the_link{}
					%% 5. delete request from callers
					%% 6. create #link{} and update links
					Link = v1attach2link(AttIn, LocHandle),%% FIXME: AttIn = not ROLE!
					% update State
					State#sessst{links = store_link(RemHandle, Link, State),
						the_links = store_the_link(not Role, Node, TheLink, State),
						callers = delete_caller({?K_ATTACH, Node}, State)};
				error ->
					%% TODO: server's request ??
					{error, dont_know_what_now}
			end
	end.

%% #'v1_0.flow'{
%%		next_incoming_id,
%%		uint mandatory incoming_window,
%%		mandatory next_outgoing_id,
%%		uint mandatory outgoing_window,
%%		handle,
%%		delivery_count,
%%		link_credit,
%%		available,
%%		boolean drain,
%%		boolean echo,
%%		properties}
handle_flow(#'v1_0.flow'{handle = undefined} = Flow, #sessst{} = State) ->
	?L_DEBUG("SESS Incoming Flow to update session ~p.", [self()]),
	NSession = update_session(State#sessst.session, Flow),
	State#sessst{session = NSession};
handle_flow(#'v1_0.flow'{handle = {_,H}} = Flow, #sessst{} = State) ->
	?L_DEBUG("SESS Incoming flow to update both session & link ~p.", [H]),
	NSession = update_session(State#sessst.session, Flow),
	case update_link(Flow, find_link(H, State)) of
		error ->
			State#sessst{session = NSession};
		Link ->
			NLinks = store_link(H, Link, State#sessst.links),
			State#sessst{session = NSession, links = NLinks}
	end.

update_session(#session{} = S, #'v1_0.flow'{} = Flow) ->
	{Flow#'v1_0.flow'.echo,
	 S#session{
		next_out_id =
			update(S#session.next_out_id, ?VALUE(Flow#'v1_0.flow'.next_incoming_id)),
		out_win =
			update(S#session.out_win, ?VALUE(Flow#'v1_0.flow'.incoming_window)),
		next_in_id =
			update(S#session.next_in_id, ?VALUE(Flow#'v1_0.flow'.next_outgoing_id)),
		in_win =
			update(S#session.in_win, ?VALUE(Flow#'v1_0.flow'.outgoing_window))
	  }
	}.

update_link(#'v1_0.flow'{handle = H}, error) ->
	?L_DEBUG("SESS Incoming Flow for non-existent remote handle ~p.", [H]),
	error;
update_link(#'v1_0.flow'{} = Flow, {ok, #link{} = L}) ->
	L#link{
		delivery_count =
			update(L#link.delivery_count, ?VALUE(Flow#'v1_0.flow'.delivery_count)),
		credit = 
			update(L#link.credit, ?VALUE(Flow#'v1_0.flow'.link_credit)),
		available = 
			update(L#link.available, ?VALUE(Flow#'v1_0.flow'.available)),
		drain = 
			update(L#link.drain, ?VALUE(Flow#'v1_0.flow'.drain))
	}.


%% #'v1_0.transfer'{
%%		handle,
%%		delivery_id,
%%		delivery_tag,
%%		message_format,
%%		settled,
%%		more,
%%		rcv_settle_mode,
%%		state,
%%		resume,
%%		aborted,
%%		batchable}
handle_transfer(Transfer, _State) ->
	?L_DEBUG("SESS handle_transfer(~120p)", [Transfer]),
	error.

%% #'v1_0.disposition'{role, first, last, settled, state, batchable}
handle_disposition(Disp, _State) ->
	?L_DEBUG("SESS handle_disposition(~120p)", [Disp]),
	error.

%% #'v1_0.detach'{handle, closed, error}
%% {'v1_0.detach',
%%		handle = {uint,0},
%%		closed = true,
%%		error = {'v1_0.error',{symbol,<<"amqp:not-found">>},undefined,undefined}}
%%
%% #'v1_0.error'{condition, description, info}
%%
handle_detach(_E, #'v1_0.detach'{error = undefined}, #sessst{}) ->
	?L_DEBUG("SESS incoming #v1detach{}, error not specified."),
	error;
handle_detach(#'v1_0.error'{condition = ?V_1_0_AMQP_ERROR_NOT_FOUND} = E,
			  #'v1_0.detach'{handle = {_,RemHandle}} = Detach,
			  #sessst{} = State) ->
	?L_DEBUG("SESS handle_detach(~120p)", [Detach]),
	%% look for stored caller {key_attach_error, rem_handle}
	CallerKey = {?K_ATTACH_ERR, RemHandle},
	case find_caller(CallerKey, State) of
		error ->
			%% not_found
			?L_DEBUG("SESS could not find caller's record ~p.", [CallerKey]);
		{ok, {From, #'v1_0.attach'{role = Role} = Att}} ->
			Node = get_node_from_attach(Att),
			gen_server:reply(From, format_error(E, [Role, Node])),
			State#sessst{callers = delete_caller(CallerKey, State)}
	end.

parse_begin([#'v1_0.begin'{} = B]) ->
	#session{
		in_ch = ?VALUE(B#'v1_0.begin'.remote_channel),
		next_out_id = ?VALUE(B#'v1_0.begin'.next_outgoing_id),
		in_win = ?VALUE(B#'v1_0.begin'.incoming_window),
		out_win = ?VALUE(B#'v1_0.begin'.outgoing_window),
		handle_max = ?VALUE(B#'v1_0.begin'.handle_max),
		props =  ?VALUE(B#'v1_0.begin'.properties)
	}.

%% TODO: We need to distinguish between AttIn and AttOut (role, src/tgt, ...)
v1attach2link(#'v1_0.attach'{} = Att, LH) ->
	#link{
		name = ?VALUE(Att#'v1_0.attach'.name),
		remote_handle = ?VALUE(Att#'v1_0.attach'.handle),
		local_handle = LH,
		%% role = ?VALUE(Att#'v1_0.attach'.role ),
		remote_role = Att#'v1_0.attach'.role,
		% local_role = Att#'v1_0.attach'.role,
		% snd_settle = ?VALUE(Att#'v1_0.attach'.snd_settle_mode),
		% rcv_settle = ?VALUE(Att#'v1_0.attach'.rcv_settle_mode),
		src = ?VALUE(Att#'v1_0.attach'.source),
		tgt = ?VALUE(Att#'v1_0.attach'.target),
		delivery_count = ?VALUE(Att#'v1_0.attach'.initial_delivery_count),
		unsettled = ?VALUE(Att#'v1_0.attach'.unsettled)
		% incomplete_unsettled = ?VALUE(Att#'v1_0.attach'.incomplete_unsettled),
		% max_msg_size = ?VALUE(Att#'v1_0.attach'.max_message_size),
		% props = ?VALUE(Att#'v1_0.attach'.properties)
	}.

link2v1attach(#link{} = _Link) ->
	#'v1_0.attach'{}.

get_node_from_attach(#'v1_0.attach'{source = undefined, target = undefined}) ->
	?L_DEBUG("SESS get_node_from_attach(1)"),
	error;
get_node_from_attach(#'v1_0.attach'{source = undefined, target = Tgt}) ->
	?L_DEBUG("SESS get_node_from_attach(2)"),
	?VALUE(Tgt#'v1_0.target'.address);
get_node_from_attach(#'v1_0.attach'{source = Src, target = undefined}) ->
	?L_DEBUG("SESS get_node_from_attach(3)"),
	?VALUE(Src#'v1_0.source'.address).

uniq_num() ->
	{MgS, S, MiS} = os:timestamp(),
	1000*1000*1000*MgS + 1000*S + MiS.

find_caller(K, #sessst{callers = C}) ->
	dict:find(K, C).

store_caller(K, Caller, #sessst{callers = C}) ->
	dict:store(K, Caller, C);
store_caller(K, Caller, C) ->
	dict:store(K, Caller, C).

delete_caller(K, #sessst{callers = C}) ->
	dict:erase(K, C);
delete_caller(K, C) ->
	dict:erase(K, C).

find_the_link(Role, Node, #sessst{the_links = TLs}) ->
	?L_DEBUG("SESS find_the_link(~p, ~p, State).", [Role, Node]),
	dict:find({Role, Node}, TLs).

delete_the_link(Role, Node, #sessst{the_links = TLs}) ->
	dict:erase({Role, Node}, TLs).

store_the_link(Role, Node, TLink, #sessst{the_links = TLs}) ->
	?L_DEBUG("SESS store_the_link({~120p,~120p},~120p,State).", [Role, Node, TLink]),
	dict:store({Role, Node}, TLink, TLs).

find_link(K, #sessst{links = Ls}) ->
	dict:find(K, Ls).

store_link(RH, L, #sessst{links = Ls}) ->
	dict:store(RH, L, Ls);
store_link(RH, L, Ls) ->
	dict:store(RH, L, Ls).

update(Old, undefined) -> Old;
update(_old, New) -> New.

inc(N) -> N+1.
dec(N) -> N-1.

%% Errors -----------------------------------------------------------

format_error(#'v1_0.error'{condition = ?V_1_0_AMQP_ERROR_NOT_FOUND,
						   description = D, info = I}, [?ROLE_RECEIVER, N]) ->
	{error,
		{not_found, N,
			iolist_to_binary(
				io_lib:format("Source Node not found. {~w,~w}", [?VALUE(D),?VALUE(I)])
			)}};
format_error(#'v1_0.error'{condition = ?V_1_0_AMQP_ERROR_NOT_FOUND,
						   description = D, info = I}, [?ROLE_SENDER, N]) ->
	{error,
		{not_found, N,
			iolist_to_binary(
				io_lib:format("Target Node not found. {~w,~w}", [?VALUE(D),?VALUE(I)])
			)}}.

%% AMQP1.0 Frames ---------------------------------------------------

%% #'v1_0.attach'{
%%		mandatory string name,
%%		mandatory		handle,
%%		mandatory		role,
%%						snd_settle_mode,
%%						rcv_settle_mode,
%%						source,
%%						target,
%%		map				unsettled,
%%		boolean			incomplete_unsettled,
%%		sequenco-no		initial_delivery_count,
%%		ulong			max_message_size,
%%		symbol multi	offered_capabilities,
%%		symbol multi	desired_capabilities,
%%		fields			properties
%%		}
amqp1_attach(Nam, Handle) ->
	#'v1_0.attach'{
			name = {utf8, Nam}
		,	handle = {uint, Handle}
		% , snd_settle_mode,
		% , rcv_settle_mode,
		% , unsettled = ?
		% , incomplete_unsettled = ?
		, initial_delivery_count = {uint, 0}
		, max_message_size = {ulong, 32768}
		% , offered_capabilities
		% , desired_capabilities
		% , properties
	  }.
%%
%% #'v1_0.source'{
%%		address, durable, expiry_policy, timeout, dynamic,
%%		dynamic_node_properties, distribution_mode, filter, default_outcome,
%%		outcomes, capabilities}).
amqp1_source(Name) ->
	#'v1_0.source'{
	     address = {utf8, Name}
	}.

%% #'v1_0.target'{address, durable, expiry_policy, timeout, dynamic,
%%			dynamic_node_properties, capabilities}
amqp1_target(Tgt) ->
	#'v1_0.target'{
		address = {utf8, Tgt}
		%, durable
		%, expiry_policy
		%, timeout
		%, dynamic
		%, dynamic_node_properties
		%, capabilities
	}.

% #'v1_0.begin'{ushort remote_channel,
%				transfer-number mandatory next_outgoing_id,
%				uint mandatory incoming_window,
%				uint mandatory outgoing_window,
%				handle handle_max,
%				symbol multiple offered_capabilities,
%				symbol multiple desired_capabilities,
%				fields properties}
amqp1_begin(#sessst{nextout = NOut} = _State) -> 
	#'v1_0.begin'{
				next_outgoing_id = {uint, NOut},
				incoming_window = {uint, 4},
				outgoing_window = {uint, 4}
	  }.


%% #'v1_0.close'{error}
amqp1_end() -> amqp1_end(undefined).
amqp1_end(E) -> #'v1_0.end'{error = E}.



%% TEST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-ifdef(TEST).

-ifdef(TEST).

amqp1_attach_test() ->
	A = amqp1_attach(),
	_B = amqp1_framing:record_to_binary(A),
	ok.


-endif.



-endif.




% end of file


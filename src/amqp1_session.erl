
-module(amqp1_session).

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").
-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% API
-export([begin_session/2, end_session/1]).
-export([get_link/2]).

-define(PROCESS, amqp1_session_process).
-define(BEGIN_SESSION, begin_session).
-define(END_SESSION, end_session).

%% API %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
begin_session(Session, #frame{} = F) ->
	?L_DEBUG("SESSION received begin session~n~120p.", [F]),
	?PROCESS:cast(Session, {?BEGIN_SESSION, F});
begin_session(Session, ChNo) ->
	?L_DEBUG("SESSION is gonna begin session in channel ~p.", [ChNo]),
	?PROCESS:call(Session, {?BEGIN_SESSION, ChNo}).

end_session(Session) ->
	gen_server:call(Session, ?END_SESSION).

%% Session - pid/{pid,link}
%% Deliver - routing, conditions, message
%% TODO: unused
transfer(_Session, _Deliver) ->
	% ? receive / send ?
	% 0. check point 3 output
	% 1. does link exist  ---\
	% 2. does source exist -\ \
	% 3. does target exist __\_\__ attach{} accordingly
	% 4. store result of 1. & 2. & 3.
	% 5. start transfer
	error.


%% Role - ?ROLE_SENDER / ?ROLE_RECEIVER
%% Node - the endpoint: either source or target
get_link(Session, #get_link{} = GetLink) ->
	?PROCESS:call(Session, GetLink).


%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%% TEST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%




% end of file


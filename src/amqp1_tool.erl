
-module(amqp1_tool).

-include("amqp1_priv.hrl").

-define(RECV_TMOUT, 5*1000).

%% -compile(export_all).
-export([receive_pick_parse/1]).
-export([erste/1]).


receive_pick_parse(Socket) ->
	{ok, Data} = amqp1_net:recv(Socket, ?RECV_TMOUT),
	?L_DEBUG("~s.incoming: ~p.", [?MODULE_STRING, Data]),
	FramesL = amqp1_framing:pick_frames(Data),
	case amqp1_framing:parse_all_frames(FramesL) of
		[ID | L1] when ID =:= ?AMQP orelse ID =:= ?SASL -> [ID | bin2rec(L1)];
		L2 when is_list(L2) -> bin2rec(L2)
	end.

bin2rec(L) ->
	[ amqp1_framing:binary_to_records(FB) || #frame{body = FB} <- L ].


erste([]) -> [];
erste([H|_T]) -> H;
erste(T) when is_tuple(T) -> element(1, T);
erste(X) -> X.




% end of file





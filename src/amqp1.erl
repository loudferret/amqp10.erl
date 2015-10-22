
-module(amqp1).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-export([start/0, stop/0]).
-export([connect/1]).

start() ->
	amqp1_app:start().

connect(#amqp1_connection_parameters{} = P) ->
	?L_DEBUG("~s:connect(~99p)", [?MODULE_STRING, P]),
	start(),
	{ok, Connection} = amqp1_connection_sup:start_connection(P),
	case amqp1_connection:connect(Connection) of
		ok -> {ok, Connection};
		E -> {error, E}
	end.

stop() ->
	application:stop(?APPID).


%% end of file



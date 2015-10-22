
-module(amqp1_app).

-behaviour(application).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

%% API
-export([start/0, stop/0]).

%% Application callbacks
-export([start/2, stop/1]).

start() ->
	case application:ensure_started(?APPID) of
		ok -> ok;
		{error, _R} -> application:start(?APPID)
	end.

stop() ->
	application:stop(?APPID).

%% ===================================================================
%% Application callbacks
%% ===================================================================


start(_StartType, _StartArgs) ->
	?L_DEBUG("AMQP 1.0 Client started."),
    amqp1_sup:start_link().

stop(_State) ->
    ok.


%% end of file



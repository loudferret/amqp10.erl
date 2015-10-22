

-module(amqp1_auth_sasl_anonymous).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile(export_all).
-endif.

-export([auth/3]).

auth(_Socket, #amqp1_connection_parameters{} = _P, _PFL) ->
	io:format("~s:auth/3~n", [?MODULE_STRING]),
	?L_DEBUG("Anonymous Auth"),
	?SC_AUTH.

%% TEST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-ifdef(TEST).

-endif.


%% end of file




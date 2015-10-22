
-module(amqp1_auth).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-export([get_auth_module/1]).
-export([supported/1]).
-export([supported_mechanisms/1]).

get_auth_module(Protocol) ->
	case Protocol of
		?SASL ->
			{ok, amqp1_auth_sasl};
		?TLS ->
			{ok, amqp1_auth_tls};	%% Does not exist yet!	
%		nonexistent ->
%			{ok, amqp1_auth_nonexistent};	%% !!! FIXME: TEST only !!!
		_ ->
			error
	end.

supported(first) ->
	hd(auth_mechanisms());
supported(P) ->
	case next_supported(P, auth_mechanisms()) of
		{_Proto, _Header} = A -> A;
		_X -> undefined
	end.

next_supported(_P, []) -> undefined;
next_supported(P, [{P,_HD}|T]) when length(T) > 0 -> hd(T);
next_supported(P, [_H|T]) -> next_supported(P, T).

%% TODO: configurable application:get_env(auth_mechanisms)
auth_mechanisms() ->
	?AUTH_SUPPORTED.

supported_mechanisms(Proto) ->
	{ok, Mod} = get_auth_module(Proto),
	[ Mech || {Mech, _Module} <- Mod:modules() ].


%% end of file




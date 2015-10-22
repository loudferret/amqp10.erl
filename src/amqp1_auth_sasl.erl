
-module(amqp1_auth_sasl).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile(export_all).
-endif.

-export([auth/2]).
-export([modules/0]).

%% 1. find out SASL Mechanism to use - concrete module
%% 2. build response #sasl.init{}
auth([#'v1_0.sasl_mechanisms'{sasl_server_mechanisms = {list, SSML}}], _P) ->
	InSML = [ M || {symbol, M} <- SSML],
	?L_DEBUG("~s:auth(~p) - #v1_0.sasl_mechanisms{}", [?MODULE_STRING, InSML]),
	Mech = first_member(InSML, amqp1_auth:supported_mechanisms(?SASL)),
	AuthM = get_auth_sasl_module(Mech),
	Resp = sasl_init(Mech),
	{AuthM, Resp};
% SASL_code - 5.3.3.6
% already defined macros V_1_0_SASL_CODE_*
% TODO: need to pass Socket or stg back to amqp1_connection
auth([#'v1_0.sasl_outcome'{code = {ubyte,0}, additional_data = AD}], _P) ->
	?L_INFO("-- logged in -- ~p --", [AD]),
	ok;
auth([#'v1_0.sasl_outcome'{code = {ubyte, C}, additional_data = AD}], _P) ->
	?L_ERROR("authentication error: ~p/~p", [C, AD]),
	error.


get_auth_sasl_module(Mech) ->
	{Mech, Mod} = lists:keyfind(Mech, 1, modules()),
	Mod.

% TODO configurable: application:get_env(sasl_modules)
modules() ->
	[{<<"ANONYMOUS">>, amqp1_auth_sasl_anonymous},
	 {?CRAMMD5, amqp1_auth_sasl_crammd5}].

first_member([], _SML) -> undefined;
first_member([M|T], SML) ->
	case lists:member(M,SML) of
		true -> M;
		false -> first_member(T, SML)
	end;
first_member(M, SML) ->
	case lists:member(M, SML) of
		true -> M;
		false -> undefined
	end.

sasl_init(SM) ->
	#'v1_0.sasl_init'{mechanism = {symbol, SM},
				  initial_response = undefined,
				  hostname = undefined}.


%% TEST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-ifdef(TEST).

-endif.


%% end of file




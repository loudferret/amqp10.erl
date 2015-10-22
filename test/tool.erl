
-module(tool).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("amqp1.hrl").
-include("amqp1_priv.hrl").
-include("test.hrl").


is_call_in_history(_, []) -> false;
is_call_in_history(Call, [{_Pid,{_Mod, Call, _}, _Ret} | _Hist]) -> true;
is_call_in_history(Call, [_|Hist]) -> is_call_in_history(Call, Hist).
	
ts() ->
	{Mega, Sec, Micro} = now(),
	Mega * 1000000 * 1000000 + Sec * 1000000 + Micro.

ts_plus_sex(S) -> 
	S * 1000 * 1000 + ts().

ts_to_time(Timestamp) ->
	{Timestamp div 1000000000000,
	 Timestamp div 1000000 rem 1000000,
	 Timestamp rem 1000000}.

rtf(F, C) ->
	file:read_file(?config(data_dir, C) ++ "/" ++ F).


%% MECK MECK %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mhist([]) -> ok;
mhist(L) ->
	lists:foreach(
		fun(Mod) ->
			ct:pal("Histery of ~p: ~p", [Mod, meck:history(Mod)])
	   	end, L).

mvalid([]) -> true;
mvalid(L) ->
	lists:foldl(
		fun(Mod, _) ->
			ct:pal("Validating ~p",[Mod]), true = meck:validate(Mod)
	   	end, [], L).

mreset([]) -> ok;
mreset(L) ->
	lists:foreach(fun(Mod) -> meck:reset(Mod) end, L).

mnew([]) -> ok;
mnew([{Mod,L}|T]) when is_list(L) ->
	ct:pal("MeckLoading ~p using ~p.",[Mod,L]),
	meck:new(Mod,L),
   	mnew(T);
mnew([Mod|T]) ->
	ct:pal("MeckLoading ~p",[Mod]),
	meck:new(Mod),
   	mnew(T).

munld() -> meck:unload().

munld([]) -> ok;
munld(L) ->
	lists:foreach(
		fun(Mod) ->
			ct:pal("Unloading ~p",[Mod]), ok = meck:unload(Mod)
	   	end, L).

%% / MECK MECK %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% end of file





















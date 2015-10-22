
-module(amqp1_framing).

-include("amqp1_priv.hrl").

-ifdef(TEST).
-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").
-include_lib("eunit/include/eunit.hrl").
-compile(export_all).
-endif.

-export([pick_frames/1]).
-export([parse_frame/1, parse_all_frames/1]).

-export([record_to_binary/1, record_to_recipe/1, recipe_to_binary/1]).
-export([binary_to_records/1, binary_to_recipe/1, recipe_to_records/1]).
-export([frame_to_binary/1, frames_to_binary/1]).
-export([value/1]).

%% should be in .hrl
-define(MDEFAULT, ?AMQP).


value(undefined) -> undefined;
value(true) -> true;
value(false) -> false;
value({_Type, Value}) -> Value;
value(Tuple) when is_tuple(Tuple) -> Tuple.


%% ... to Records

%% binaryInput -> [binaryFrame0, ..., binaryFrameN]
pick_frames(Data) ->
	pick_frames(Data, []).

pick_frames(<<>>, OutL) ->
	{lists:reverse(OutL), <<>>};
pick_frames(<<"AMQP", 0, 1, 0, 0, Data/binary>>, OutL) ->
	pick_frames(Data, [?AMQP|OutL]);
pick_frames(<<"AMQP", 2, 1, 0, 0, Data/binary>>, []) ->
	pick_frames(Data, [?TLS]);
pick_frames(<<"AMQP", 3, 1, 0, 0, Data/binary>>, []) ->
	pick_frames(Data, [?SASL]);
pick_frames(<<Size:32, _Rest/binary>> = Data, OutL) when byte_size(Data) >= Size ->
	<<Frame:Size/binary, NData/binary>> = Data,
	pick_frames(NData, [Frame|OutL]);
pick_frames(Rest, OutL) ->
	{lists:reverse(OutL), Rest}.


%% binaryFrame -> #frame{}

parse_all_frames(FramesL) when is_list(FramesL) ->
	parse_all_frames(FramesL, []).

parse_all_frames([], OutL) ->
	lists:reverse(OutL);
parse_all_frames([Frame|T], OutL) ->
	parse_all_frames(T, [parse_frame(Frame)|OutL]).
	
parse_frame(ProtoID) when ProtoID =:= ?AMQP
						 orelse ProtoID =:= ?TLS
						 orelse ProtoID =:= ?SASL ->
   ProtoID;	
parse_frame(<<Size:32, DOFF:8, 1:8, 0:16, Rest/binary>> = _Frame) ->
	EHS = 4 * DOFF - 8,
	FBS = Size - 4 * DOFF,
	<<_EH:EHS/binary, FB:FBS/binary, Nic/binary>> = Rest,
	0 = byte_size(Nic), %% TODO: not needed
	#frame{type = ?SASL, channel = 0, body = FB};
parse_frame(<<Size:32, DOFF:8, 0:8, Chann:16, Rest/binary>> = _Frame) ->
	EHS = 4 * DOFF - 8,
	FBS = Size - 4 * DOFF,
	<<_EH:EHS/binary, FB:FBS/binary, Nic/binary>> = Rest,
	0 = byte_size(Nic), %% TODO: not needed
	#frame{type = ?AMQP, channel = Chann, body = FB}.


%% binaryPayload -> Records, returns a list of list(s)
binary_to_records(B) ->
	rabbit_amqp1_0_framing:decode_bin(B).

%% binaryPayload -> [Recipe]
binary_to_recipe(B) ->
	%% rabbit_amqp1_0_binary_parser:parse(B).
	rabbit_amqp1_0_binary_parser:parse_all(B).

%% Recipe -> Records, R is a tuple
recipe_to_records(R) ->
	rabbit_amqp1_0_framing:decode(R).




%% ... to binaryPayload

%% Record -> binaryPayload
record_to_binary(R) ->
	iolist_to_binary(rabbit_amqp1_0_framing:encode_bin(R)).

%% Record -> Recipe 
record_to_recipe(R) ->
	rabbit_amqp1_0_framing:encode(R).

%% Recipe -> binaryPayload
recipe_to_binary(R) ->
	iolist_to_binary(rabbit_amqp1_0_binary_generator:generate(R)).

%% [#frame{}0, ..., #frame{}N] -> binaryOutput
frames_to_binary(FL) when is_list(FL) ->
	binary:list_to_bin(lists:map(fun frame_to_binary/1, FL)).

%% #frame{} -> binaryFrame -> 
frame_to_binary(#frame{type = T, channel = Ch, body = B}) ->
	rabbit_amqp1_0_binary_generator:build_frame(Ch, T, B).

%% TEST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-ifdef(TEST).

-endif.








%% end of file






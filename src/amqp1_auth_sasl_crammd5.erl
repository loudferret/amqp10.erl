

-module(amqp1_auth_sasl_crammd5).

-include("amqp1.hrl").
-include("amqp1_priv.hrl").

-include_lib("rabbitmq_amqp1_0/include/rabbit_amqp1_0_framing.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile(export_all).
-endif.

-export([auth/2]).


%% TODO: Do I need to check if challenge is base64ed ?
auth([#'v1_0.sasl_challenge'{challenge = {binary, Challenge}}],
	 #amqp1_connection_parameters{user = U, password = P}) ->
	?L_DEBUG("~s:auth(~120p)", [?MODULE_STRING, Challenge]),
	{amqp1_auth_sasl, sasl_response(Challenge, U, P)}.

%% Locals -----------------------------------------------------------

sasl_response(Ch, U, P) ->
	#'v1_0.sasl_response'{response = {binary, cmd5_response(U, P, Ch)}}.

% 1 The challenge is base64-decoded.
% 2	The decoded challenge is hashed using HMAC-MD5, with a shared secret
%   (typically, the user's password, or a hash thereof) as the secret key.
% 3 The hashed challenge is converted to a string of lowercase hex digits.
% 4 The username and a space character are prepended to the hex digits.
% 5 The concatenation is then base64-encoded and sent to the server.
cmd5_response(U, P, Ch) ->
	%% FIXME: QPid returns nonEncoded64 string
	%%		  DecCh = base64:decode(Ch),
	%%		  HashedCh = crypto:hmac(md5, P, DecCh),
	HashedCh = crypto:hmac(md5, P, Ch),
	Digest = hexbinary(HashedCh),
	%Digest = crypto:hmac(md5, P, Ch),
	%Prepended = <<U/binary, " ", Digest/binary>>,
	<<U/binary, " ", Digest/binary>>
	% Stringed = hexbinary(crypto:hmac(md5, P, base64:decode(Ch))), 
	% base64:encode(<<U/binary, " ", Stringed/binary>>)
	%base64:encode(Prepended)
	.

hexbinary(<<X:128/big-unsigned-integer>>) ->
	    iolist_to_binary(lists:flatten(io_lib:format("~32.16.0b", [X]))).


%% TEST -------------------------------------------------------------

-ifdef(TEST).

-endif.


%% end of file




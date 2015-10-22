
-define(NONE, none).

%% Application ID
-define(APPID, amqp1).

%% modes
-define(AMQP, amqp).
-define(SASL, sasl).
-define(TLS,  tls).

%% frame types
-define(FT_AMQP, 0).
-define(FT_SASL, 1).
-define(DEF_FT, ?FT_AMQP).

%% Protocol Defaults
-define(AMQP1_HEADER, <<"AMQP", 0, 1, 0, 0>>).
-define(AMQP1_DPORT, 5672).
%% -define(TCP_CONNECT_OPTIONS, [binary, {active,false}, {packet,4}]).
-define(TCP_CONNECT_OPTIONS, [binary, {active,false}]).

%% 0 - authenticated
%% 2 - TLS
%% 3 - SASL
-define(AUTH_SASL, <<"AMQP", 3, 1, 0, 0>>).
-define(AUTH_TLS,  <<"AMQP", 2, 1, 0, 0>>).
%% TODO: 'nonexistent' is only for testing !!!!
%-define(AUTH_SUPPORTED, [{nonexistent, <<"AMQP", 9, 1, 0, 0>>},
-define(AUTH_SUPPORTED, [{?SASL, ?AUTH_SASL},
						 {?TLS, ?AUTH_TLS}]).

-define(CRAMMD5, <<"CRAM-MD5">>).

-define(SC_AUTH,             0).
-define(SC_NAUTH_CRED,       1).
-define(SC_NAUTH_SYSERR,     2).
-define(SC_NAUTH_PERMERR,    3).
-define(SC_NAUTH_TRANSERR,   4).
-define(SC_NAUTH,            -1).

-record(frame, {type = ?AMQP, channel, body}).

-define(DEFLOC, "en_US").
-record(server_props, {id, hostname, max_frame_size, channel_max,
					   idle_time_out, offered, desired,
					   outgoing_locales = ?DEFLOC,
					   incoming_locales = ?DEFLOC}).

%% APIs

-define(ENCODED, process_encoded_data).
-define(DECODED, process_decoded_data).

%% session data
%% Link ID for API
-record(the_link, {session, role, name = ?NONE, remote_handle = ?NONE}).


%% logging %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-define(L_DEBUG(T),		error_logger:info_msg("D~p:" ++ T, [self()])). 
-define(L_DEBUG(F,D),	error_logger:info_msg("D~p:" ++ F, [self()] ++ D)).
-define(L_INFO(F,D),	error_logger:info_msg(F,D)).
-define(L_WARN(F,D),	error_logger:warning_msg(F,D)).
-define(L_ERROR(F,D),	error_logger:error_msg(F,D)).


%% Generals


-define(ERST(A), amqp1_tool:erste(A)).
-define(VALUE(V), amqp1_framing:value(V)).

-define(ALLIS(X, A, B), A =:= X andalso B =:= X).
-define(ALLIS(X, A, B, C), A =:= X andalso B =:= X andalso C =:= X).

% end of file


%
%% to be able to mock gen_tcp
%

-module(amqp1_net).

-include("amqp1_priv.hrl").

-define(DEF_TCP_TMOUT, infinity).
%% -define(RECV_TMOUT, 5*1000).

-export([connect/3, send/2, recv/1, recv/2]).
-export([controlling/2]).
-export([]).


%% Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

connect(Addr, Port, Options) -> connect(Addr, Port, Options, ?DEF_TCP_TMOUT).
connect(Addr, Port, Options, Tmout) -> gen_tcp:connect(Addr, Port, Options, Tmout).

send(Socket, Data) -> gen_tcp:send(Socket, Data).

recv(Socket) -> recv(Socket, 0, ?DEF_TCP_TMOUT).
recv(Socket, Timeout) -> recv(Socket, 0, Timeout).
recv(Socket, Length, Timeout) -> gen_tcp:recv(Socket, Length, Timeout).

controlling(Socket, Pid) -> gen_tcp:controlling_process(Socket, Pid).

% end of file









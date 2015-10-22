

-define(ROLE_SENDER, false).
-define(ROLE_RECEIVER, true).

-record(amqp1_connection_parameters, 
				{host, virtual, port, user, password, options = []}).

%% sesion commands

-record(get_link, {role, node}).		%% TODO: What is sufficient node?


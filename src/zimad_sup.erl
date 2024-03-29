-module(zimad_sup).
-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->

    {ok, {
            #{strategy => one_for_one, intensity => 10, period => 10},
            [
                #{
                    id => zimad,
                    start => {zimad, start_link, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [zimad]
                }
            ]
    }}.


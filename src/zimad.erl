-module(zimad).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-export([
          register/1,
          authorize/1,
          get_profile/1,
          win/1,
          buy_stars/2,
          gdpr_erase_profile/1
        ]).

-export([md5/1]).
-export([erase_session/1]).
-export([is_session/1]).
-export([get_uid_by_token/1]).

-define(SESSION_TIME, 15 * 60 * 1000).
-define(CoinsForStar, 10).


-define(SERVER, ?MODULE).
-record(state, {}).

%%
md5(S) ->
  string:to_upper(
    lists:flatten([io_lib:format("~2.16.0b",[N]) || <<N>> <= erlang:md5(S)])
  ).

%%
erase_session (UID) ->
  timer:sleep(?SESSION_TIME),
  zimad ! {expire, UID}.

%%
is_session(UID) ->

  case ets:lookup(tokens, UID) of
   []  -> false;
    _ -> true
  end.

%%
get_info(UID) ->

  case ets:lookup(users, UID) of
  [{UID, Usermap}]  ->
        Usermap;
    _ ->
      []
  end.

%%
get_uid_by_token(Token) ->

  case ets:match_object(tokens, {'$1', Token}) of

    [{UID, Token}] -> UID;
    _ -> []

  end.

%%
update_level (Token) ->

  UID = get_uid_by_token(Token),
  UserMap = get_info(UID),
  Fun = fun(V) -> V + 1 end,
  Newmap = maps:update_with(level,Fun,UserMap),

%%  we caould have return the new level but the terms say nothing about that,
%% so we just return the status of the update without the actual level

  ets:insert(users, {UID, Newmap}).


buy(UID, Count) when is_integer(Count) ->

  CurMap = get_info(UID),

  CurStars = maps:get(stars, CurMap),
  CurCoins = maps:get(coins, CurMap),

   if CurCoins < Count * ?CoinsForStar ->
       {CurStars, failure};
     true ->

        NewCoins = CurCoins - Count * ?CoinsForStar,
        NewStars = CurStars + Count,
        NewMap1 = maps:update(coins, NewCoins, CurMap),
        NewMap2 = maps:update(stars, NewStars, NewMap1),
        ets:insert(users, {UID, NewMap2}),
       {ok, NewStars}
   end;
buy(UID, _Count) ->
  CurMap = get_info(UID),
  CurStars = maps:get(stars, CurMap),
  {failure, CurStars}.


%%{
%%"uid": "<some_string>", // Уникальный id игрока, присваивается при регистрации
%%"nickname": "<some_string>", // Уникальное имя игрока, записывается при регистрации
%%"coins": 100, // Баланс пользователя в монетах, 100 монет выдаётся при регистрации
%%"stars": 0, // Игровые звёздочки, покупаются по цене 1звезда=10монет
%%"level": 0 // Игровой уровень игрока
%%}


register (Nickname) ->
  gen_server:call(?MODULE, {register, Nickname}).

authorize(UID) ->
  gen_server:call(?MODULE, {authorize, UID}).

get_profile(Token) ->
  gen_server:call(?MODULE, {get_profile, Token}).

win(Token) ->
  gen_server:call(?MODULE, {win_level, Token}).

buy_stars(Token, Stars)->
  gen_server:call(?MODULE, {buy_stars, Token, Stars}).

gdpr_erase_profile(Token) ->
  gen_server:call(?MODULE, {erase_profile, Token}).


start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


init([]) ->

  rand:seed(exs1024s),

  ets:new(users, [named_table, public]),
  ets:new(sessions, [named_table, public]),
  ets:new(tokens, [named_table, public]),

  {ok, #state{}}.

%%
handle_call({register, Nickname}, _From, State) ->

  UID = md5(Nickname),
  Result = case ets:lookup(users, UID) of
       [] ->
                            ets:insert(users, {UID, #{nickname => list_to_binary(Nickname),
                                                      uid => list_to_binary(UID),
                                                      coins => 100,
                                                      stars => 0,
                                                      level => 0}}),
                            UID;
       [{UID, _Usermap}] ->

                jiffy:encode(#{status => error, errmsg => <<"User is alreagy registered">>})
  end,
  {reply, Result, State};

%%
handle_call({authorize, UID}, _From, State) ->

  Res = case ets:lookup(users, UID) of

     [] ->
              jiffy:encode(#{status =>  error, errmsg => <<"No such UID">>});
   [{UID,
     _Usermap}] ->

     case is_session(UID) of
       true ->
               jiffy:encode(#{status => error, errmsg => <<"User is already authorized!">>});
       false ->
         Token = uuid:to_string(uuid:uuid1()),
         ets:insert(tokens, {UID, Token}),
         spawn(zimad, erase_session,[UID]),
         Token
    end
  end,
  {reply, Res, State};

%%
handle_call({get_profile, Token}, _From, State) ->

  Res = case ets:match_object(tokens, {'$1', Token}) of
   [{UID,
     Token}] ->
                get_info(UID);
    _ ->
                []
  end,
  {reply, jiffy:encode(Res), State};


handle_call({win_level, Token}, _From, State) ->

Result =  case is_session(get_uid_by_token(Token)) of
    true  ->
            update_level(Token);
    _ ->
        jiffy:encode(#{status => error, errmsg => <<"Cannot update, probably user is invalid">>})
  end,

  {reply, Result, State};


%%
handle_call({buy_stars, Token, Count}, _From, State) ->

  UID = get_uid_by_token(Token),
  io:format("UID:~p~n", [UID]),

  Result = case is_session(UID) of
    true  ->
            {Status, Stars} = buy(UID, Count),
            jiffy:encode(#{status => Status, stars => Stars});
    false ->
            jiffy:encode(#{status => failure, ermsg => <<"No such user">>})
  end,
  {reply, Result, State};

%%
handle_call({erase_profile, Token}, _From, State) ->

  Result = case is_session(get_uid_by_token(Token)) of
     false ->
              jiffy:encode(#{status => error});
     true ->
              UID = get_uid_by_token(Token),
              ets:delete(tokens, UID),
              ets:delete(users, UID),
              jiffy:encode(#{status => ok})
  end,
  {reply, Result, State};

%%
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Request, State) ->
  {noreply, State}.


handle_info({expire, UID}, State) ->

    io:format("Session for nickname ~p has expired!~n", [UID]),
    ets:delete(tokens, UID),

  {noreply, State};

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

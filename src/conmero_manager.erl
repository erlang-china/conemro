%% -------------------------------------------------------------------
%% Copyright (c) 2013 Honghu Huang (huanghonghu@adsage.com)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%% -------------------------------------------------------------------


-module(conmero_manager).
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("conmero.hrl").

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0, start/0, stop/0]).
-export([get_key_hash/1]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start()->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:call(?MODULE,stop).


%% ====================================================================
%% Behavioural functions 
%% ====================================================================
-record(state, {}).

%% init/1
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:init-1">gen_server:init/1</a>
-spec init(Args :: term()) -> Result when
    Result :: {ok, State}
            | {ok, State, Timeout}
            | {ok, State, hibernate}
            | {stop, Reason :: term()}
            | ignore,
    State :: term(),
    Timeout :: non_neg_integer() | infinity.
%% ====================================================================
init([]) ->
    load_config(),
    {ok, #state{}}.


%% handle_call/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_call-3">gen_server:handle_call/3</a>
-spec handle_call(Request :: term(), From :: {pid(), Tag :: term()}, State :: term()) -> Result when
    Result :: {reply, Reply, NewState}
            | {reply, Reply, NewState, Timeout}
            | {reply, Reply, NewState, hibernate}
            | {noreply, NewState}
            | {noreply, NewState, Timeout}
            | {noreply, NewState, hibernate}
            | {stop, Reason, Reply, NewState}
            | {stop, Reason, NewState},
    Reply :: term(),
    NewState :: term(),
    Timeout :: non_neg_integer() | infinity,
    Reason :: term().
%% ====================================================================
handle_call(load_config, _From, State) ->
    Reply = load_config(),
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.


%% handle_cast/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_cast-2">gen_server:handle_cast/2</a>
-spec handle_cast(Request :: term(), State :: term()) -> Result when
    Result :: {noreply, NewState}
            | {noreply, NewState, Timeout}
            | {noreply, NewState, hibernate}
            | {stop, Reason :: term(), NewState},
    NewState :: term(),
    Timeout :: non_neg_integer() | infinity.
%% ====================================================================
handle_cast(_Msg, State) ->
    {noreply, State}.


%% handle_info/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_info-2">gen_server:handle_info/2</a>
-spec handle_info(Info :: timeout | term(), State :: term()) -> Result when
    Result :: {noreply, NewState}
            | {noreply, NewState, Timeout}
            | {noreply, NewState, hibernate}
            | {stop, Reason :: term(), NewState},
    NewState :: term(),
    Timeout :: non_neg_integer() | infinity.
%% ====================================================================
handle_info(_Info, State) ->
    {noreply, State}.


%% terminate/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:terminate-2">gen_server:terminate/2</a>
-spec terminate(Reason, State :: term()) -> Any :: term() when
    Reason :: normal
            | shutdown
            | {shutdown, term()}
            | term().
%% ====================================================================
terminate(_Reason, _State) ->
    ok.


%% code_change/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:code_change-3">gen_server:code_change/3</a>
-spec code_change(OldVsn, State :: term(), Extra :: term()) -> Result when
    Result :: {ok, NewState :: term()} | {error, Reason :: term()},
    OldVsn :: Vsn | {down, Vsn},
    Vsn :: term().
%% ====================================================================
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% ====================================================================
%% Internal functions
%% ====================================================================
load_config()->
    {ok, Filename} = application:get_env(config),
    {ok, Terms}    = file:consult(Filename),
    ConmeroConfigs = proplists:get_value(conmero, Terms),
    CallAlgorithmTypeList = proplists:get_value(call_algorithm_type, ConmeroConfigs),
    [begin
         AppsList = proplists:get_value(CallAlgorithmType, ConmeroConfigs),
         init_apps(CallAlgorithmType, ConmeroConfigs, AppsList)
     end
    || CallAlgorithmType <- CallAlgorithmTypeList].

init_apps(_CallAlgorithmType,_Terms, [])->ok;
init_apps(_CallAlgorithmType,_Terms, undefined)->ok;
init_apps( CallAlgorithmType, Terms, AppsList)->
    [begin 
         ServerNodes = proplists:get_value(App, Terms),
         insert_app_into_ets(CallAlgorithmType, App, ServerNodes)
     end||App<-AppsList].

insert_app_into_ets(CallAlgorithmType, App, ServerNodes)->
    AppTableName = conmero_app_table:create_app_table(App),
    AppInfo      = generate_app(CallAlgorithmType, App, ServerNodes),

    ets:insert(AppTableName, AppInfo).


generate_app(_CallAlgorithmType, App, undefined)->
    #conmero_app_info{application = App};
generate_app(CallAlgorithmType, App, [])->
    generate_app(CallAlgorithmType, App, undefined);

generate_app(direct, App, [ServerNode|T])->
    case proplists:get_value(id, ServerNode) of
        Id when Id=:=1->
            generate_direct_app(App, ServerNode);
        _->
            generate_app(direct, App, T)
    end;
generate_app(consistent, App, ServerNodes)->
    NodeTableName = conmero_app_table:create_node_table(App),
    AppNodeConfig = generate_consistent_app_node(App, ServerNodes, []),

    ets:insert(NodeTableName, AppNodeConfig),
    #conmero_app_info{
        application         = App,
        call_algorithm_type = 1}.

generate_direct_app(App, ServerNode)->
    case proplists:get_value(node_status, ServerNode) of
        online -> 
            ModSender     = proplists:get_value(mod_sender,      ServerNode),
            MasterNode    = proplists:get_value(master_node,     ServerNode),
            SlaveNodeTmp  = proplists:get_value(slave_node,      ServerNode),
            Timeout       = proplists:get_value(timeout,         ServerNode),
            NodeTag       = proplists:get_value(node_tag,        ServerNode),
            NodeSwitchTmp = proplists:get_value(switch_to_slave, ServerNode),
            NodeSwitch    = get_int_TorF(NodeSwitchTmp, on),

            {SyncFun, ASysnFun} = get_sender_functions(ModSender),
            SlaveNode =
                case SlaveNodeTmp of
                    undefined ->
                        MasterNode;
                    _->
                        SlaveNodeTmp
                end,
            #conmero_app_info{
                    application         = App,
                    call_algorithm_type = 0,
                    master_node         = MasterNode,
                    slave_node          = SlaveNode,
                    sync_func           = SyncFun,
                    async_func          = ASysnFun,
                    timeout             = Timeout,
                    switch_to_slave     = NodeSwitch,
                    node_tag            = NodeTag};
        _ ->
            []
    end.

generate_consistent_app_node(_App, [], AccOut)->AccOut;
generate_consistent_app_node( App, [ServerNode|T], AccIn)->
    case proplists:get_value(node_status, ServerNode) of
        online -> 
            Id            = proplists:get_value(id,              ServerNode),
            ModSender     = proplists:get_value(mod_sender,      ServerNode),
            MasterNode    = proplists:get_value(master_node,     ServerNode),
            SlaveNodeTmp  = proplists:get_value(slave_node,      ServerNode),
            Timeout       = proplists:get_value(timeout,         ServerNode),
            VNodeNums     = proplists:get_value(v_node_num,      ServerNode),
            HashBaseKey   = proplists:get_value(hash_base_key,   ServerNode),
            NodeTag       = proplists:get_value(node_tag,        ServerNode),
            NodeSwitchTmp = proplists:get_value(switch_to_slave, ServerNode),
            SlaveNode =
                case SlaveNodeTmp of
                    undefined ->
                        MasterNode;
                    _->
                        SlaveNodeTmp
                end,
            NodeSwitch   = get_int_TorF(NodeSwitchTmp, on),
            ConmeroNodes =
                make_nodes(App, Id, ModSender, MasterNode, SlaveNode, NodeSwitch,
                           Timeout, VNodeNums, HashBaseKey, NodeTag),
            generate_consistent_app_node(App, T, lists:append(ConmeroNodes, AccIn));
        _ ->
            generate_consistent_app_node(App, T, AccIn)
    end.

get_int_TorF( F, S) when F=:=S->1;
get_int_TorF(_F,_S) ->0.

make_nodes( App, Id, ModSender, MasterNode, SlaveNode, NodeSwitch,
            Timeout, VNodeNums, HashBaseKey, NodeTag)
        when is_atom(App),
             is_integer(Id),
             is_integer(NodeSwitch),
             is_integer(Timeout),
             is_integer(VNodeNums), VNodeNums > 0,
             is_list(NodeTag)->
    make_nodes_1(App,Id, ModSender, MasterNode, SlaveNode, NodeSwitch,
                 Timeout, 0, VNodeNums, HashBaseKey, NodeTag, []);
make_nodes( _App,_Id,_ModSender,_MasterNode,_SlaveNode,_NodeSwitch,
            _Timeout,_VNodeNums,_HashBaseKey,_NodeTag)->
    [].

make_nodes_1(_App,_Id,_ModSender,_MasterNode,_SlaveNode,_NodeSwitch,
             _Timeout,_BaseVNode, 0,_HashBaseKey,_NodeTag, AccOut)->
    AccOut;
make_nodes_1(_App,_Id,_ModSender,_MasterNode,_SlaveNode,_NodeSwitch,
             _Timeout, BaseVNode, VNodeId,_HashBaseKey,_NodeTag, AccOut) 
        when BaseVNode == VNodeId ->
    AccOut;
make_nodes_1( App, Id, ModSender, MasterNode, SlaveNode, NodeSwitch,
              Timeout, BaseVNode, VNodeId, HashBaseKey, NodeTag, AccOut)->

    Key                 = io_lib:format("~s:~b", [HashBaseKey, VNodeId]),
    KeyHash             = get_key_hash(Key),
    {SyncFun, ASysnFun} = get_sender_functions(ModSender),
    NodeRec = #conmero_app_node{
                    id              = Id,
                    application     = App,
                    sync_func       = SyncFun,
                    async_func      = ASysnFun,
                    master_node     = MasterNode,
                    slave_node      = SlaveNode,
                    timeout         = Timeout,
                    switch_to_slave = NodeSwitch,
                    v_node_id       = VNodeId,
                    hash_index      = KeyHash,
                    node_tag        = NodeTag},
    make_nodes_1(App, Id, ModSender, MasterNode, SlaveNode, NodeSwitch, Timeout,
                 BaseVNode, VNodeId-1, HashBaseKey, NodeTag, [NodeRec | AccOut]).


get_sender_functions([])->get_sender_functions(undefined);
get_sender_functions(undefined)->{undefined, undefined};
get_sender_functions(Sender)->
    {fun Sender:call/3, fun Sender:cast/2}.


get_key_hash(Key)->
    ByteKeyHash                 = erlang:md5(Key),
    <<KeyHash:32/big,_/binary>> = ByteKeyHash,
    KeyHash.


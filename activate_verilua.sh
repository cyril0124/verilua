#!/bin/bash

lua=luajit2.1

source "$VERILUA_HOME/$lua/bin/activate"

export LD_LIBRARY_PATH=$VERILUA_HOME/shared:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/$lua/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/$lua/lib/lua/5.1:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/$lua/lib/lua/5.1/socket:$LD_LIBRARY_PATH

export LUA_PATH="\
./?.lua;$(pwd)/?.lua;$(pwd)/src/lua/?.lua;\
$VERILUA_HOME/luajit2.1/share/lua/5.1/?.lua;\
$VERILUA_HOME/luajit2.1/share/lua/5.1/?/init.lua;\
$VERILUA_HOME/src/lua/?.lua;\
$VERILUA_HOME/src/lua/verilua/?.lua;\
$VERILUA_HOME/src/lua/thirdparty_lib/?.lua;\
$VERILUA_HOME/extern/luafun/?.lua;\
$VERILUA_HOME/extern/debugger.lua/?.lua;\
"

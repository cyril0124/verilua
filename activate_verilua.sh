#!/usr/bin/env bash

export PATH=$VERILUA_HOME/tools:$PATH
export PATH=$VERILUA_HOME/luajit-pro/luajit2.1/bin:$PATH

export LD_LIBRARY_PATH=$VERILUA_HOME/shared:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/shared:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/luajit-pro/luajit2.1/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/luajit-pro/luajit2.1/lib/lua/5.1:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/luajit-pro/luajit2.1/lib/lua/5.1/socket:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/wave_vpi/target/release:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/luajit-pro/target/release:$LD_LIBRARY_PATH

# Used by libverilua
export LUA_LIB=$VERILUA_HOME/luajit-pro/luajit2.1/lib
export LUA_LIB_NAME=luajit-5.1
export LUA_LINK=shared

export LUA_PATH="\
./?.lua;\
$VERILUA_HOME/luajit-pro/luajit2.1/share/lua/5.1/?.lua;\
$VERILUA_HOME/luajit-pro/luajit2.1/share/lua/5.1/?/init.lua;\
$VERILUA_HOME/luajit-pro/luajit2.1/share/luajit-2.1/?.lua;\
$VERILUA_HOME/src/lua/?.lua;\
$VERILUA_HOME/src/lua/verilua/?.lua;\
$VERILUA_HOME/src/lua/verilua/vpiml/?.lua;\
$VERILUA_HOME/src/lua/verilua/sva/?.lua;\
$VERILUA_HOME/src/lua/verilua/coverage/?.lua;\
$VERILUA_HOME/src/lua/verilua/handles/?.lua;\
$VERILUA_HOME/src/lua/verilua/scheduler/?.lua;\
$VERILUA_HOME/src/lua/verilua/random/?.lua;\
$VERILUA_HOME/src/lua/verilua/utils/?.lua;\
$VERILUA_HOME/src/lua/thirdparty_lib/?.lua;\
$VERILUA_HOME/extern/luafun/?.lua;\
$VERILUA_HOME/extern/LuaPanda/Debugger/?.lua;\
$VERILUA_HOME/extern/debugger.lua/?.lua;\
$VERILUA_HOME/extern/luajit_tcc/?.lua;\
"

export LUA_CPATH="\
$VERILUA_HOME/luajit-pro/luajit2.1/lib/lua/5.1/?.so;\
$VERILUA_HOME/luajit-pro/luajit2.1/lib/lua/5.1/?/?.so\
$VERILUA_HOME/extern/LuaPanda/Debugger/debugger_lib/?.so;\
"

. "$VERILUA_HOME/extern/luajit_tcc/setvars.sh"

unset VERILUA_USE_NIX

export CONFIG_TCCDIR=$VERILUA_HOME/extern/luajit_tcc/tinycc/install

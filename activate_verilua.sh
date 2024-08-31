#!/usr/bin/env bash

lua=luajit2.1

export LD_LIBRARY_PATH=$VERILUA_HOME/shared:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/luajit-pro/$lua/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/luajit-pro/$lua/lib/lua/5.1:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/luajit-pro/$lua/lib/lua/5.1/socket:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/wave_vpi/target/release:$LD_LIBRARY_PATH

export LUA_PATH="\
./?.lua;$(pwd)/?.lua;$(pwd)/src/lua/?.lua;\
$VERILUA_HOME/luajit-pro/$lua/share/lua/5.1/?.lua;\
$VERILUA_HOME/luajit-pro/$lua/share/lua/5.1/?/init.lua;\
$VERILUA_HOME/src/lua/?.lua;\
$VERILUA_HOME/src/lua/verilua/?.lua;\
$VERILUA_HOME/src/lua/thirdparty_lib/?.lua;\
$VERILUA_HOME/extern/luafun/?.lua;\
$VERILUA_HOME/extern/debugger.lua/?.lua;\
$VERILUA_HOME/extern/luajit_tcc/?.lua;\
$VERILUA_HOME/extern/lua_inline_c/?.lua;\
$VERILUA_HOME/extern/lua_inline_c/?/?.lua;\
"

. "$VERILUA_HOME/extern/lua_inline_c/setvars.sh"
. "$VERILUA_HOME/extern/luajit_tcc/setvars.sh"

export CONFIG_TCCDIR=$VERILUA_HOME/extern/luajit_tcc/tinycc/install

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

export LUA_PATH="\
./?.lua;$(pwd)/?.lua;$(pwd)/src/lua/?.lua;\
$VERILUA_HOME/luajit-pro/luajit2.1/share/lua/5.1/?.lua;\
$VERILUA_HOME/luajit-pro/luajit2.1/share/lua/5.1/?/init.lua;\
$VERILUA_HOME/luajit-pro/luajit2.1/share/luajit-2.1/?.lua;\
$VERILUA_HOME/src/gen/?.lua;\
$VERILUA_HOME/src/lua/?.lua;\
$VERILUA_HOME/src/lua/verilua/?.lua;\
$VERILUA_HOME/src/lua/verilua/coverage/?.lua;\
$VERILUA_HOME/src/lua/verilua/handles/?.lua;\
$VERILUA_HOME/src/lua/verilua/scheduler/?.lua;\
$VERILUA_HOME/src/lua/verilua/random/?.lua;\
$VERILUA_HOME/src/lua/verilua/utils/?.lua;\
$VERILUA_HOME/src/lua/thirdparty_lib/?.lua;\
$VERILUA_HOME/extern/luafun/?.lua;\
$VERILUA_HOME/extern/debugger.lua/?.lua;\
$VERILUA_HOME/extern/luajit_tcc/?.lua;\
$VERILUA_HOME/extern/lua_inline_c/?.lua;\
$VERILUA_HOME/extern/lua_inline_c/?/?.lua;\
"

. "$VERILUA_HOME/extern/lua_inline_c/setvars.sh"
. "$VERILUA_HOME/extern/luajit_tcc/setvars.sh"

unset VERILUA_USE_NIX

export CONFIG_TCCDIR=$VERILUA_HOME/extern/luajit_tcc/tinycc/install

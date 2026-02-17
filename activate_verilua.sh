#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Check if VERILUA_HOME is set
# -----------------------------------------------------------------------------
if [ -z "$VERILUA_HOME" ]; then
    echo "Error: VERILUA_HOME is not set!" >&2
    echo "Please set VERILUA_HOME before sourcing this script." >&2
    return 1 2>/dev/null || exit 1
fi

# -----------------------------------------------------------------------------
# PATH configuration
# -----------------------------------------------------------------------------
export PATH="$VERILUA_HOME/tools:$PATH"
export PATH="$VERILUA_HOME/luajit-pro/luajit2.1/bin:$PATH"

# -----------------------------------------------------------------------------
# Library paths (LD_LIBRARY_PATH)
# -----------------------------------------------------------------------------
export LD_LIBRARY_PATH="$VERILUA_HOME/luajit-pro/luajit2.1/lib:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$VERILUA_HOME/luajit-pro/luajit2.1/lib/lua/5.1:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$VERILUA_HOME/luajit-pro/luajit2.1/lib/lua/5.1/socket:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$VERILUA_HOME/wave_vpi/target/release:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$VERILUA_HOME/luajit-pro/target/release:$LD_LIBRARY_PATH"

# Optional: Add shared libs if exists
if [ -d "$VERILUA_HOME/shared" ]; then
    export LD_LIBRARY_PATH="$VERILUA_HOME/shared:$LD_LIBRARY_PATH"
fi

# -----------------------------------------------------------------------------
# Lua configuration (used by libverilua)
# -----------------------------------------------------------------------------
export LUA_LIB="$VERILUA_HOME/luajit-pro/luajit2.1/lib"
export LUA_LIB_NAME="luajit-5.1"
export LUA_LINK="shared"

# -----------------------------------------------------------------------------
# LUA_PATH configuration
# All Lua module search paths
# -----------------------------------------------------------------------------
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
$VERILUA_HOME/extern/debugger.lua/?.lua;\
$VERILUA_HOME/extern/luajit_tcc/?.lua;\
"

# -----------------------------------------------------------------------------
# LUA_CPATH configuration
# All Lua C module search paths
# -----------------------------------------------------------------------------
export LUA_CPATH="\
$VERILUA_HOME/luajit-pro/luajit2.1/lib/lua/5.1/?.so;\
$VERILUA_HOME/luajit-pro/luajit2.1/lib/lua/5.1/?/?.so;\
"

# -----------------------------------------------------------------------------
# TinyCC configuration
# -----------------------------------------------------------------------------
if [ -f "$VERILUA_HOME/extern/luajit_tcc/setvars.sh" ]; then
    source "$VERILUA_HOME/extern/luajit_tcc/setvars.sh"
fi

export CONFIG_TCCDIR="$VERILUA_HOME/extern/luajit_tcc/tinycc/install"


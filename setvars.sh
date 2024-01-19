#!/bin/bash

lua=luajit2.1

source "$VERILUA_HOME/$lua/bin/activate"

export LD_LIBRARY_PATH=$VERILUA_HOME/shared:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/$lua/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/$lua/lib/lua/5.1:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$VERILUA_HOME/$lua/lib/lua/5.1/socket:$LD_LIBRARY_PATH

# !! You should modify these two variables according to your project.
export LUA_SCRIPT=$VERILUA_HOME/src/lua/main/LuaMainTemplate.lua
export PRJ_TOP=$PWD
export DUT_TOP="Unknown"

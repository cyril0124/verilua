#!/bin/bash

source $VERILUA_HOME/activate_verilua.sh

# !! You should modify these two variables according to your project.
export LUA_SCRIPT=$PWD/src/lua/main/LuaMain.lua
export PRJ_TOP=$PWD
export DUT_TOP="Unknown"
export SIM="vcs"
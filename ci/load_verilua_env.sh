#!/usr/bin/env bash

set -ex

# Check if VERILUA_HOME is provided
if [ -z "$1" ]; then
    echo -e "Error: VERILUA_HOME is not provided"
    echo -e "\n\tUsage: $0 <verilua_home>\n"
    exit 1
fi

verilua_home=$1

echo "VERILUA_HOME=$verilua_home" >> $GITHUB_ENV
export VERILUA_HOME=$verilua_home # Make this available to current shell
echo "[load_verilua_env.sh] VERILUA_HOME is: $VERILUA_HOME"

source $VERILUA_HOME/activate_verilua.sh

echo "PATH=$PATH" >> $GITHUB_ENV
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> $GITHUB_ENV
echo "LUA_PATH=$LUA_PATH" >> $GITHUB_ENV
echo "LUA_CPATH=$LUA_CPATH" >> $GITHUB_ENV
echo "CONFIG_TCCDIR=$CONFIG_TCCDIR" >> $GITHUB_ENV

echo "[load_verilua_env.sh] PATH is: $PATH"
echo "[load_verilua_env.sh] LD_LIBRARY_PATH is: $LD_LIBRARY_PATH"
echo "[load_verilua_env.sh] LUA_PATH is: $LUA_PATH"
echo "[load_verilua_env.sh] LUA_CPATH is: $LUA_CPATH"
echo "[load_verilua_env.sh] CONFIG_TCCDIR is: $CONFIG_TCCDIR"
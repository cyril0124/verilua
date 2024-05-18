#!/usr/bin/env bash

if [ -d "$(pwd)/luajit2.1" ]
then
    echo "luajit2.1 exists."
    export VERILUA_HOME=$(pwd); source activate_verilua.sh

    luarocks install penlight
    luarocks install luasocket
    luarocks install lsqlite3
    # luarocks install inspect
    luarocks install argparse
    luarocks install busted
    luarocks install linenoise
    luarocks list
else
    echo "luajit2.1 does not exist. start installing..."
    
    source $(pwd)/install_lua.sh
    export VERILUA_HOME=$(pwd); source activate_verilua.sh

    luarocks install penlight
    luarocks install luasocket
    luarocks install lsqlite3
    # luarocks install inspect
    luarocks install argparse
    luarocks install busted
    luarocks install linenoise
    luarocks list
fi
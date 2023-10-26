#!/bin/bash

if [ -d "$(pwd)/luajit2.1" ]
then
    echo "luajit2.1 exists."
    source setup_verilua.sh

    luarocks install penlight
    luarocks install luasocket
    luarocks install lsqlite3
    luarocks list
else
    echo "luajit2.1 does not exist. start installing..."
    
    source $(pwd)/install_lua.sh
    source setup_verilua.sh

    luarocks install penlight
    luarocks install luasocket
    luarocks install lsqlite3
    luarocks list
fi
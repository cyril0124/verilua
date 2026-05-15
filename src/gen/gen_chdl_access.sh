#!/bin/bash
set -e

cd "$(dirname "$0")"

luajit gen_chdl_access.lua

DEST="$VERILUA_HOME/src/lua/verilua/handles"
cp ./out/ChdlAccessSingle.lua "$DEST/ChdlAccessSingle.lua"
cp ./out/ChdlAccessDouble.lua "$DEST/ChdlAccessDouble.lua"
cp ./out/ChdlAccessMulti.lua "$DEST/ChdlAccessMulti.lua"

echo "Copied to $DEST"

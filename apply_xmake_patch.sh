#!/bin/bash

curr_dir=$(pwd)
mkdir -p ~/.xmake/rules/verilua
cp $curr_dir/scripts/.xmake/rules/verilua/xmake.lua ~/.xmake/rules/verilua
mkdir -p ~/.xmake/toolchains/vcs
cp $curr_dir/scripts/.xmake/toolchains/vcs/xmake.lua ~/.xmake/toolchains/vcs
mkdir -p ~/.xmake/toolchains/wave_vpi
cp $curr_dir/scripts/.xmake/toolchains/wave_vpi/xmake.lua ~/.xmake/toolchains/wave_vpi


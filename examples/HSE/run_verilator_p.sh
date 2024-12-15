#!/usr/bin/env bash

set -e

PRJ_DIR=$(pwd)

cd $PRJ_DIR/verilua
source setvars.sh
cd $PRJ_DIR

export SIM=verilator

# vl-verilator-p is different from vl-verilator in that it require a verilator 
# configuration file which controls the accessibility of verilog modules.
vl-verilator-p --cc --exe --build -Mdir sim_build -j 0 \
    verilator_main.cpp \
    tb_top.sv Top.v \
    config.vlt # This is a mandatory file with suffix `.vlt` and vl-verilator-p will check the existence of this file by suffix.

./sim_build/Vtb_top
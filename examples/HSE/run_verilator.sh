#!/usr/bin/env bash

set -e

PRJ_DIR=$(pwd)

cd $PRJ_DIR/verilua
source setvars.sh
cd $PRJ_DIR

export SIM=verilator

vl-verilator --cc --exe --build -Mdir sim_build -j 0 \
    verilator_main.cpp \
    tb_top.sv Top.v

./sim_build/Vtb_top
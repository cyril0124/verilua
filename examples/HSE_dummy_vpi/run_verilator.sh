#!/usr/bin/env bash

set -e

PRJ_DIR=$(pwd)

cd $PRJ_DIR/verilua
source setvars.sh
cd $PRJ_DIR

export SIM=verilator

vl-verilator-p --cc --exe --build -Mdir sim_build_vpi -j 0 \
    -CFLAGS "-std=c++20" \
    --Wno-WIDTHEXPAND \
    ./verilator/verilator_main.cpp \
    tb_top.sv Top.v \
    ./verilator/config.vlt \
    --trace \
    -o tb_top

./sim_build_vpi/tb_top
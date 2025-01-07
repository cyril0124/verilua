#!/usr/bin/env bash

set -e

PRJ_DIR=$(pwd)

cd $PRJ_DIR/verilua
source setvars.sh
cd $PRJ_DIR

export SIM=verilator

bash run_dpi_exporter.sh

vl-verilator-dpi --cc --exe --build -Mdir sim_build_dpi -j 0 \
    -CFLAGS "-std=c++20 -DDPI" \
    --Wno-WIDTHEXPAND \
    ./verilator/verilator_main.cpp \
    ./.dpi_exporter/tb_top.sv \
    ./.dpi_exporter/Top.v ./.dpi_exporter/dpi_func.cpp \
    --trace \
    -o tb_top

./sim_build_dpi/tb_top
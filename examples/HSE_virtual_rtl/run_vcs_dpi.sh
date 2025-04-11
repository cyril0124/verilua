#!/usr/bin/env bash

set -e

PRJ_DIR=$(pwd)

cd $PRJ_DIR/verilua
source setvars.sh
cd $PRJ_DIR

export SIM=vcs

bash run_dpi_exporter.sh

vl-vcs-dpi -full64 -sverilog ./.dpi_exporter/top.sv ./.dpi_exporter/dpi_func.cpp -o simv_dpi

./simv_dpi
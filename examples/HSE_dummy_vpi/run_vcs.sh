#!/usr/bin/env bash

set -e

PRJ_DIR=$(pwd)

cd $PRJ_DIR/verilua
source setvars.sh
cd $PRJ_DIR

export SIM=vcs

vl-vcs -full64 -sverilog tb_top.sv Top.v -o simv

./simv
#!/usr/bin/env bash
# End-to-end test for `vl-verilator --vl-mem-direct`:
#   one-shot verilator --build, wrapper-driven table generation + .so compile
#   (with include filters forwarded), then run a custom main that provides the
#   mem_direct contract symbols and asserts native read/write through verilua.
set -e
cd "$(dirname "$0")"

: "${VERILUA_HOME:?VERILUA_HOME must be set}"
export SIM=verilator

rm -rf sim_build mem_direct_generated.cpp libmem_direct.so run.log

"$VERILUA_HOME/tools/vl-verilator" --vl-mem-direct \
    --vl-mem-direct-include 'tb_top.clk' \
    --vl-mem-direct-include 'glob:tb_top.uut.reg32' \
    --vl-mem-direct-include 'glob:tb_top.uut.vec_reg' \
    --cc --exe --build -Mdir sim_build -j 0 --top-module tb_top \
    --Wno-WIDTHTRUNC --Wno-WIDTHEXPAND \
    -CFLAGS "-std=c++20" main.cpp tb_top.sv ../rtl/top.sv

test -f libmem_direct.so

MD_VLV_DIR=$PWD VL_CFG_FILE=$PWD/verilua/cfg.lua VL_MEM_DIRECT_SO=$PWD/libmem_direct.so \
    ./sim_build/Vtb_top 2>&1 | tee run.log

grep -q '\[test_mem_direct_vl_verilator\] PASS' run.log
rm -f run.log
echo "[run.sh] OK"

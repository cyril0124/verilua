#!/usr/bin/env bash
# End-to-end test for `vl-verilator-p --vl-mem-direct`: same as run.sh but with
# a user .vlt controlling visibility instead of the default --public-flat-rw.
set -e
cd "$(dirname "$0")"

: "${VERILUA_HOME:?VERILUA_HOME must be set}"
export SIM=verilator

rm -rf sim_build_p mem_direct_generated.cpp libmem_direct.so run_p.log

"$VERILUA_HOME/tools/vl-verilator-p" --vl-mem-direct \
    --vl-mem-direct-include 'tb_top.clk' \
    --vl-mem-direct-include 'glob:tb_top.uut.reg32' \
    --vl-mem-direct-include 'glob:tb_top.uut.vec_reg' \
    --cc --exe --build -Mdir sim_build_p -j 0 --top-module tb_top \
    --Wno-WIDTHTRUNC --Wno-WIDTHEXPAND \
    -CFLAGS "-std=c++20" config.vlt main.cpp tb_top.sv ../rtl/top.sv

test -f libmem_direct.so

MD_VLV_DIR=$PWD VL_CFG_FILE=$PWD/verilua/cfg.lua VL_MEM_DIRECT_SO=$PWD/libmem_direct.so \
    ./sim_build_p/Vtb_top 2>&1 | tee run_p.log

grep -q '\[test_mem_direct_vl_verilator\] PASS' run_p.log
rm -f run_p.log
echo "[run_p.sh] OK"

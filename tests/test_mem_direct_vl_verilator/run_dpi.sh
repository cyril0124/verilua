#!/usr/bin/env bash
# End-to-end test for `vl-verilator-dpi --vl-mem-direct` (dummy_vpi flow):
# dpi_exporter rewrites the RTL and exports only the clock; un-exported
# signals (reg32 / vec_reg) are reached natively through mem_direct.
# reg16 is exported as `meta_only`: static meta from the dpi table, no DPI
# accessor/tick sampling, pinned by the generated dpi_exporter.public.vlt,
# value accessed through mem_direct.
set -e
cd "$(dirname "$0")"

: "${VERILUA_HOME:?VERILUA_HOME must be set}"
export SIM=verilator

rm -rf sim_build_dpi .dpi_exporter mem_direct_generated.cpp libmem_direct.so run_dpi.log

"$VERILUA_HOME/tools/dpi_exporter" -c dpi_cfg.lua -q --top-clock clk ../rtl/top.sv tb_top.sv --no-cache

# meta_only artifacts: public pin present, accessor/tick sampling absent.
grep -qF 'public_flat_rd -module "top" -var "reg16"' .dpi_exporter/dpi_exporter.public.vlt
grep -qF '"metaOnly": true' .dpi_exporter/dpi_exporter.meta.json
! grep -qF 'VERILUA_DPI_EXPORTER_tb_top_uut_reg16' .dpi_exporter/dpi_func.cpp
! grep -qF 'tb_top.uut.reg16' .dpi_exporter/tb_top.sv

"$VERILUA_HOME/tools/vl-verilator-dpi" --vl-mem-direct \
    --vl-mem-direct-include 'tb_top.clk' \
    --vl-mem-direct-include 'glob:tb_top.uut.reg32' \
    --vl-mem-direct-include 'glob:tb_top.uut.reg16' \
    --vl-mem-direct-include 'glob:tb_top.uut.vec_reg' \
    --cc --exe --build -Mdir sim_build_dpi -j 0 --top-module tb_top \
    --Wno-WIDTHTRUNC --Wno-WIDTHEXPAND \
    -CFLAGS "-std=c++20 -DVL_DPI_EXP_CALL_ENV_STEP" config.vlt main_dpi.cpp \
    .dpi_exporter/dpi_exporter.public.vlt \
    .dpi_exporter/tb_top.sv .dpi_exporter/top.sv .dpi_exporter/dpi_func.cpp

test -f libmem_direct.so

MD_VLV_DIR=$PWD MD_VLV_DPI=1 VL_CFG_FILE=$PWD/verilua/cfg.lua VL_MEM_DIRECT_SO=$PWD/libmem_direct.so \
    ./sim_build_dpi/Vtb_top 2>&1 | tee run_dpi.log

grep -q '\[test_mem_direct_vl_verilator\] PASS' run_dpi.log
rm -f run_dpi.log
echo "[run_dpi.sh] OK"

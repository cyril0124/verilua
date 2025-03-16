#!/usr/bin/env bash

set -e

dpi_exporter -c ./verilua/dpi_cfg.lua -q Top.v tb_top.sv
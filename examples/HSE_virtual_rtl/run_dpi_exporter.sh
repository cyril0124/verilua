#!/usr/bin/env bash

set -e

dpi_exporter -c ./verilua/dpi_cfg.lua ./top.sv --no-cache

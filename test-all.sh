#!/usr/bin/env bash
set -euo pipefail

JOBS=$(( $(nproc) / 2 ))
[ "$JOBS" -lt 1 ] && JOBS=1

VL_TEST_JOBS="$JOBS" xmake run test "$@"

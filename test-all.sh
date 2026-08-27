#!/usr/bin/env bash
set -euo pipefail

# Pin the project to this script's tree: xmake otherwise walks up from the cwd
# and lands on the parent checkout when this runs from a git worktree.
PRJ_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

JOBS=$(( $(nproc) / 2 ))
[ "$JOBS" -lt 1 ] && JOBS=1

VL_TEST_JOBS="$JOBS" xmake run -P "$PRJ_DIR" test "$@"

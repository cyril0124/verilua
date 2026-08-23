#!/usr/bin/env bash
# Install the git hooks declared in .pre-commit-config.yaml (run once per clone).
# Uses prek (Rust re-implementation of pre-commit, same config format).
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v prek >/dev/null 2>&1; then
    echo "==> installing prek"
    curl -LsSf https://github.com/j178/prek/releases/latest/download/prek-installer.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

# pre-push is needed for the cargo-clippy hook.
prek install --hook-type pre-commit --hook-type pre-push

echo "==> done. Check everything with: prek run --all-files"

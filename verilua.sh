#!/usr/bin/env bash

current_shell=$(ps -p $$ -ocomm=)

if [[ "$current_shell" == *bash* ]]; then
    script_file=$(realpath "${BASH_SOURCE[0]}")
elif [[ "$current_shell" == *zsh* ]]; then
    script_file=$0
else
    echo "[verilua.sh] Unknown shell, current shell is: $current_shell"
    exit 1
fi

script_dir=$(dirname $(realpath $script_file))

export VERILUA_HOME=$script_dir
export XMAKE_GLOBALDIR=$VERILUA_HOME/scripts
source $VERILUA_HOME/activate_verilua.sh

function load_verilua() {
    export VERILUA_HOME=$script_dir
    export XMAKE_GLOBALDIR=$VERILUA_HOME/scripts
    echo "[verilua.sh] Loading verilua..."
    echo "[verilua.sh] VERILUA_HOME is: $VERILUA_HOME"
    echo "[verilua.sh] XMAKE_GLOBALDIR is: $XMAKE_GLOBALDIR"
    source $VERILUA_HOME/activate_verilua.sh
}

function unload_verilua() {
    echo "[verilua.sh] Unloading verilua..."
    echo "[verilua.sh] VERILUA_HOME is: $VERILUA_HOME"
    echo "[verilua.sh] XMAKE_GLOBALDIR is: $XMAKE_GLOBALDIR"
    unset VERILUA_HOME
    unset XMAKE_GLOBALDIR
}

function test_verilua() {
    if ! command -v iverilog &> /dev/null && 
       ! command -v verilator &> /dev/null && 
       ! command -v vcs &> /dev/null; then
        echo "[test_verilua] No simulator found, skipping verilua test."
        return
    fi

    curr_dir=$(pwd)
    cd $VERILUA_HOME/examples/simple_ut_env

    if command -v iverilog &> /dev/null; then
        SIM=iverilog xmake b -P . &> /dev/null
        SIM=iverilog xmake r -P . &> /dev/null
        rm -rf build
    fi

    if command -v verilator &> /dev/null; then
        SIM=verilator xmake b -P . &> /dev/null
        SIM=verilator xmake r -P . &> /dev/null
        rm -rf build
    fi

    if command -v vcs &> /dev/null; then
        SIM=vcs xmake b -P . &> /dev/null
        SIM=vcs xmake r -P . &> /dev/null
        rm -rf build
    fi

    cd $curr_dir
    echo "[test_verilua] Test verilua finished!"
}

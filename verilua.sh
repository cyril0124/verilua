#!/usr/bin/env bash

current_shell=$(ps -p $$ -ocomm=)

if [[ "$current_shell" == *bash* ]]; then
    script_file=$(realpath "${BASH_SOURCE[0]}")
elif [[ "$current_shell" == *zsh* ]]; then
    script_file=$0
else
    echo "Unknown shell"
fi

script_dir=$(dirname $(realpath $script_file))

export VERILUA_HOME=$script_dir
source $VERILUA_HOME/activate_verilua.sh

export XMAKE_GLOBALDIR=$VERILUA_HOME/scripts

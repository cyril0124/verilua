#!/usr/bin/env bash

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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
    echo "[verilua.sh] VERILUA_HOME is: ${GREEN}$VERILUA_HOME${NC}"
    echo "[verilua.sh] XMAKE_GLOBALDIR is: ${GREEN}$XMAKE_GLOBALDIR${NC}"
    source $VERILUA_HOME/activate_verilua.sh
}

function unload_verilua() {
    echo "[verilua.sh] Unloading verilua..."
    echo "[verilua.sh] VERILUA_HOME is: ${GREEN}$VERILUA_HOME${NC}"
    echo "[verilua.sh] XMAKE_GLOBALDIR is: ${GREEN}$XMAKE_GLOBALDIR${NC}"
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

function update_verilua() {
    curr_dir=$(pwd)
    auto_yes=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                auto_yes=true
                shift
                ;;
            *)
                echo "Unknown option: $1, available options are: -y, --yes" >&2
                echo "Usage: $0 [-y | --yes]" >&2
                cd $curr_dir
                return 1
                ;;
        esac
    done

    if [ -f $VERILUA_HOME/Cargo.toml ]; then
        echo -e "\t❌ Unable to update verilua, maybe you are using verilua built from source not from release."
        return
    fi

    if [ ! -f $VERILUA_HOME/VERSION ] || [ ! -f $VERILUA_HOME/COMMIT_HASH ]; then
        echo -e "\t❌ Unable to update verilua, maybe you are using verilua built from source not from release."
        return
    fi

    curr_version=$(cat $VERILUA_HOME/VERSION)
    curr_commit=$(cat $VERILUA_HOME/COMMIT_HASH)
    remote_repo="https://github.com/cyril0124/verilua.git"
    temp_dir="/tmp/update_verilua"

    echo "[update_verilua] 📌 Check verilua version..."
    echo -e "\t✅ Verilua home is: ${GREEN}$VERILUA_HOME${NC}"
    echo -e "\t✅ Current verilua version is: ${GREEN}$curr_version($curr_commit)${NC}"

    mkdir -p $temp_dir
    cd $temp_dir
    rm -rf $temp_dir/verilua
    git clone --depth 1 $remote_repo &> /dev/null
    cd verilua
    latest_version=$(git describe --tags --abbrev=0 2>/dev/null)
    latest_commit=$(git rev-parse HEAD)
    release_time=$(git show -s --format=%ci $latest_version)
    cd $curr_dir

    echo -e "\t✅ Latest verilua version is: ${GREEN}$latest_version($latest_commit)${NC}"
    echo -e "\t✅ Latest verilua commit hash is: ${GREEN}$latest_commit${NC}"
    echo -e "\t✅ Latest verilua release time is: ${GREEN}$release_time${NC}"

    if [[ $curr_version == $latest_version && $curr_commit == $latest_commit ]]; then
        echo -e "\t✅ Verilua is already up to date."
        return
    fi

    reason=""
    if [[ $curr_version != $latest_version ]]; then
        reason="version mismatch"
    fi
    if [[ $curr_commit != $latest_commit ]]; then
        reason="commit hash mismatch"
    fi

    echo "[update_verilua] ⏳ Updating verilua($reason)..."
    if $auto_yes; then
        answer="y"
    else
        echo -e -n "\t❗ Update to $latest_version($latest_commit)? (y/n): "
        read answer
    fi

    if [ "$answer" != "y" ]; then
        echo -e "\t❌ ${RED}Update cancelled${RESET}\n"
        return
    fi

    release_url="https://github.com/cyril0124/verilua/releases/download/$latest_version/$(cat $VERILUA_HOME/DIST_INFO)"

    mkdir -p $temp_dir/dist
    rm -rf $temp_dir/dist/latest.zip
    rm -rf $temp_dir/dist/verilua

    echo -e "\t✅ Downloading latest verilua..."
    curl -# -L "$release_url" -o "$temp_dir/dist/latest.zip"
    echo -e "\t✅ Downloaded latest verilua to: ${GREEN}$temp_dir/dist/latest.zip${NC}"
    echo -e "\t✅ Unzipping latest verilua..."
    unzip $temp_dir/dist/latest.zip -d $temp_dir/dist/verilua &> /dev/null
    echo -e "\t✅ Unzipped latest verilua to: ${GREEN}$temp_dir/dist/verilua${NC}"

    mv $VERILUA_HOME $VERILUA_HOME.old
    cp -r $temp_dir/dist/verilua $VERILUA_HOME
    echo -e "\t✅ Previous verilua home is: ${GREEN}$VERILUA_HOME.old${NC}"
    echo -e "\t✅ Successfully updated verilua to: ${GREEN}$latest_version($latest_commit)${NC}"
}
#!/usr/bin/env bash

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -n "$BASH_VERSION" ]; then
    script_file=$(realpath "${BASH_SOURCE[0]}")
elif [ -n "$ZSH_VERSION" ]; then
    script_file=$(realpath "$0")
else
    current_shell=$(ps -p $$ -ocomm=)
    echo -e "${YELLOW}[verilua.sh] Warning: Unknown shell.${NC}"
    echo -e "\tAttempting to proceed, but behavior might be unpredictable."
    echo -e "\tCurrent shell seems to be: ${BOLD}$current_shell${NC}"
    script_file=$(realpath "$0")
    if [ ! -f "$script_file" ]; then
        echo -e "${RED}[verilua.sh] Error: Could not determine script path in this shell.${NC}"
        exit 1
    fi
fi

script_dir=$(dirname $(realpath $script_file))

function build_wave_vpi_main_fsdb() {
    NO_DEPS=1 NO_CPPTRACE=1 xmake b -P $VERILUA_HOME/src/wave_vpi wave_vpi_main_fsdb
    which wave_vpi_main_fsdb &> /dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}[verilua.sh] Error: wave_vpi_main_fsdb build failed!${NC}"
        return 1
    fi
    echo -e "${GREEN}[verilua.sh] wave_vpi_main_fsdb builded successfully!${NC}"
}

# If wave_vpi_main_fsdb is not found and VERDI_HOME is set, try to build it
if ! command -v wave_vpi_main_fsdb >/dev/null 2>&1 && [ -n "$VERDI_HOME" ]; then
    echo -e "${YELLOW}[verilua.sh] wave_vpi_main_fsdb not found and VERDI_HOME is set, attempting to build it...${NC}"
    build_wave_vpi_main_fsdb
fi

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
    case_dir=$VERILUA_HOME/examples/guided_tour/

    if command -v iverilog &> /dev/null; then
        SIM=iverilog xmake b -P $case_dir &> /dev/null
        SIM=iverilog xmake r -P $case_dir &> /dev/null
        rm -rf build
        echo "[test_verilua] successfully tested verilua with iverilog"
    fi

    if command -v verilator &> /dev/null; then
        SIM=verilator xmake b -P $case_dir &> /dev/null
        SIM=verilator xmake r -P $case_dir &> /dev/null
        rm -rf build
        echo "[test_verilua] successfully tested verilua with verilator"
    fi

    if command -v vcs &> /dev/null; then
        SIM=vcs xmake b -P $case_dir &> /dev/null
        SIM=vcs xmake r -P $case_dir &> /dev/null
        rm -rf build
        echo "[test_verilua] successfully tested verilua with vcs"
    fi

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
    git clone $remote_repo &> /dev/null
    cd verilua
    latest_version=$(git describe --tags --abbrev=0 2>/dev/null)
    git checkout $latest_version &> /dev/null
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

    verilua_home_basename=$(basename $VERILUA_HOME)
    verilua_home_dirname=$(dirname $VERILUA_HOME)
    verilua_home_old="${verilua_home_dirname}/.${verilua_home_basename}.old"
    mv $VERILUA_HOME $verilua_home_old
    cp -r $temp_dir/dist/verilua $VERILUA_HOME
    echo -e "\t✅ Previous verilua home is: ${GREEN}$verilua_home_old${NC}"
    echo -e "\t✅ Successfully updated verilua to: ${GREEN}$latest_version($latest_commit)${NC}"
}

#!/usr/bin/env bash

BOLD='\033[1m'
DIM='\033[2m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC}  ${1}"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC}  ${1}"
}

log_success() {
    echo -e "${GREEN}✓${NC}  ${1}"
}

log_error() {
    echo -e "${RED}✗${NC}  ${1}"
}

log_step() {
    echo -e "${CYAN}▶${NC}  ${1}"
}

# Detect script directory
if [ -n "$BASH_VERSION" ]; then
    script_file=$(realpath "${BASH_SOURCE[0]}")
elif [ -n "$ZSH_VERSION" ]; then
    script_file=$(realpath "$0")
else
    current_shell=$(ps -p $$ -ocomm=)
    log_warning "Unknown shell detected: ${BOLD}${current_shell}${NC}"
    echo -e "   Attempting to proceed, but behavior might be unpredictable."
    script_file=$(realpath "$0")
    if [ ! -f "$script_file" ]; then
        log_error "Could not determine script path in this shell."
        exit 1
    fi
fi

script_dir=$(dirname "$script_file")

# Build wave_vpi_main_fsdb if needed
build_wave_vpi_main_fsdb() {
    log_step "Building wave_vpi_main_fsdb..."
    
    local build_log
    build_log=$(mktemp)

    # Run build and capture all output to a temporary file
    if NO_DEPS=1 NO_CPPTRACE=1 xmake b -P "$VERILUA_HOME/src/wave_vpi" wave_vpi_main_fsdb > "$build_log" 2>&1; then
        # Check for success marker and binary existence
        if grep -q "build ok" "$build_log" && command -v wave_vpi_main_fsdb >/dev/null 2>&1; then
            log_success "wave_vpi_main_fsdb built successfully!"
            rm -f "$build_log"
            return 0
        fi
    fi

    log_error "wave_vpi_main_fsdb build failed! Log output:"
    cat "$build_log"
    rm -f "$build_log"
    return 1
}

# Initialize environment
export VERILUA_HOME="$script_dir"
export XMAKE_GLOBALDIR="$VERILUA_HOME/scripts"
source "$VERILUA_HOME/activate_verilua.sh"

# Auto-build wave_vpi_main_fsdb if VERDI_HOME is set
if ! command -v wave_vpi_main_fsdb >/dev/null 2>&1 && [ -n "$VERDI_HOME" ]; then
    log_info "wave_vpi_main_fsdb not found but VERDI_HOME is set"
    build_wave_vpi_main_fsdb
fi

# Load verilua environment
load_verilua() {
    export VERILUA_HOME="$script_dir"
    export XMAKE_GLOBALDIR="$VERILUA_HOME/scripts"
    
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}                  ${GREEN}Loading Verilua${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "VERILUA_HOME    = ${GREEN}${VERILUA_HOME}${NC}"
    log_info "XMAKE_GLOBALDIR = ${GREEN}${XMAKE_GLOBALDIR}${NC}"
    echo ""
    
    source "$VERILUA_HOME/activate_verilua.sh"
    log_success "Verilua environment loaded!"
    echo ""
}

# Unload verilua environment
unload_verilua() {
    echo ""
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║${NC}                 ${YELLOW}Unloading Verilua${NC}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Previous VERILUA_HOME    = ${DIM}${VERILUA_HOME}${NC}"
    log_info "Previous XMAKE_GLOBALDIR = ${DIM}${XMAKE_GLOBALDIR}${NC}"
    
    unset VERILUA_HOME
    unset XMAKE_GLOBALDIR
    
    echo ""
    log_success "Verilua environment unloaded!"
    echo ""
}

# Test verilua with available simulators
test_verilua() {
    local simulators=()
    
    # Detect available simulators
    command -v iverilog &> /dev/null && simulators+=("iverilog")
    command -v verilator &> /dev/null && simulators+=("verilator")
    command -v vcs &> /dev/null && simulators+=("vcs")
    
    if [ ${#simulators[@]} -eq 0 ]; then
        log_warning "No simulators found (iverilog, verilator, vcs)"
        log_info "Skipping verilua test"
        return 0
    fi
    
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}                  ${CYAN}Testing Verilua${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Available simulators: ${GREEN}${simulators[*]}${NC}"
    echo ""
    
    local curr_dir=$(pwd)
    local case_dir="$VERILUA_HOME/examples/guided_tour"
    local test_passed=0
    local test_failed=0
    
    cd "$case_dir" || {
        log_error "Failed to enter test directory: $case_dir"
        return 1
    }
    
    for sim in "${simulators[@]}"; do
        log_step "Testing with ${MAGENTA}${sim}${NC}..."
        
        if SIM="$sim" xmake b -P "$case_dir" &> /dev/null && \
           SIM="$sim" xmake r -P "$case_dir" &> /dev/null; then
            log_success "Test passed with ${GREEN}${sim}${NC}"
            ((test_passed++))
        else
            log_error "Test failed with ${RED}${sim}${NC}"
            ((test_failed++))
        fi
        
        rm -rf build
    done
    
    cd "$curr_dir" || return 1
    
    echo ""
    echo -e "${BOLD}Test Results:${NC}"
    echo -e "  ${GREEN}✓${NC} Passed: ${GREEN}${test_passed}${NC}"
    if [ $test_failed -gt 0 ]; then
        echo -e "  ${RED}✗${NC} Failed: ${RED}${test_failed}${NC}"
    else
        echo -e "  ${DIM}✗${NC} Failed: ${DIM}${test_failed}${NC}"
    fi
    echo ""
    
    if [ $test_failed -eq 0 ]; then
        log_success "All verilua tests passed!"
    else
        log_warning "Some tests failed"
        return 1
    fi
    
    return 0
}

# Update verilua to the latest version
update_verilua() {
    local curr_dir=$(pwd)
    local auto_yes=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                auto_yes=true
                shift
                ;;
            *)
                log_error "Unknown option: ${RED}$1${NC}"
                echo "   Available options: -y, --yes"
                echo "   Usage: update_verilua [-y | --yes]"
                cd "$curr_dir" || return 1
                return 1
                ;;
        esac
    done
    
    # Check if this is a source build
    if [ -f "$VERILUA_HOME/Cargo.toml" ]; then
        log_error "Unable to update verilua"
        echo "   This appears to be a source build, not a release version"
        echo "   Please update manually using: ${GREEN}git pull${NC}"
        return 1
    fi
    
    if [ ! -f "$VERILUA_HOME/VERSION" ] || [ ! -f "$VERILUA_HOME/COMMIT_HASH" ]; then
        log_error "Unable to update verilua"
        echo "   VERSION or COMMIT_HASH file not found"
        echo "   This may be a source build, not a release version"
        return 1
    fi
    
    echo ""
    echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${MAGENTA}║${NC}                 ${MAGENTA}Updating Verilua${NC}"
    echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local curr_version=$(cat "$VERILUA_HOME/VERSION")
    local curr_commit=$(cat "$VERILUA_HOME/COMMIT_HASH")
    local remote_repo="https://github.com/cyril0124/verilua.git"
    local temp_dir="/tmp/update_verilua_$$"
    
    log_step "Checking current version..."
    echo ""
    log_info "Verilua home: ${GREEN}${VERILUA_HOME}${NC}"
    log_info "Current version: ${GREEN}${curr_version}${NC} ${DIM}(${curr_commit})${NC}"
    echo ""
    
    # Create temp directory and clone repo
    log_step "Fetching latest version information..."
    mkdir -p "$temp_dir"
    cd "$temp_dir" || {
        log_error "Failed to create temp directory"
        return 1
    }
    
    if ! git clone "$remote_repo" &> /dev/null; then
        log_error "Failed to clone repository"
        cd "$curr_dir" || return 1
        rm -rf "$temp_dir"
        return 1
    fi
    
    cd verilua || {
        log_error "Failed to enter cloned repository"
        cd "$curr_dir" || return 1
        rm -rf "$temp_dir"
        return 1
    }
    
    local latest_version=$(git describe --tags --abbrev=0 2>/dev/null)
    if [ -z "$latest_version" ]; then
        log_error "Failed to get latest version tag"
        cd "$curr_dir" || return 1
        rm -rf "$temp_dir"
        return 1
    fi
    
    git checkout "$latest_version" &> /dev/null
    local latest_commit=$(git rev-parse HEAD)
    local release_time=$(git show -s --format=%ci "$latest_version")
    
    echo ""
    log_info "Latest version: ${GREEN}${latest_version}${NC} ${DIM}(${latest_commit})${NC}"
    log_info "Release time: ${CYAN}${release_time}${NC}"
    echo ""
    
    # Check if update is needed
    if [[ "$curr_version" == "$latest_version" && "$curr_commit" == "$latest_commit" ]]; then
        log_success "Verilua is already up to date!"
        cd "$curr_dir" || return 1
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Determine update reason
    local reason=""
    if [[ "$curr_version" != "$latest_version" ]]; then
        reason="version: ${YELLOW}${curr_version}${NC} → ${GREEN}${latest_version}${NC}"
    elif [[ "$curr_commit" != "$latest_commit" ]]; then
        reason="commit hash mismatch"
    fi
    
    log_warning "Update available: ${reason}"
    echo ""
    
    # Confirm update
    local answer="n"
    if $auto_yes; then
        answer="y"
        log_info "Auto-confirming update (--yes flag)"
    else
        echo -n -e "${BOLD}   Update to ${GREEN}${latest_version}${NC} ${DIM}(${latest_commit})${NC}? [y/N]: ${NC}"
        read answer
    fi
    
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        log_warning "Update cancelled by user"
        cd "$curr_dir" || return 1
        rm -rf "$temp_dir"
        return 0
    fi
    
    echo ""
    
    # Download and install
    if [ ! -f "$VERILUA_HOME/DIST_INFO" ]; then
        log_error "DIST_INFO file not found"
        cd "$curr_dir" || return 1
        rm -rf "$temp_dir"
        return 1
    fi
    
    local release_url="https://github.com/cyril0124/verilua/releases/download/${latest_version}/$(cat "$VERILUA_HOME/DIST_INFO")"
    local dist_dir="$temp_dir/dist"
    
    mkdir -p "$dist_dir"
    
    log_step "Downloading latest release..."
    if ! curl -# -L "$release_url" -o "$dist_dir/latest.zip"; then
        log_error "Failed to download release"
        cd "$curr_dir" || return 1
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_step "Extracting archive..."
    if ! unzip -q "$dist_dir/latest.zip" -d "$dist_dir/verilua"; then
        log_error "Failed to extract archive"
        cd "$curr_dir" || return 1
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_step "Installing new version..."
    
    local verilua_home_basename=$(basename "$VERILUA_HOME")
    local verilua_home_dirname=$(dirname "$VERILUA_HOME")
    local verilua_home_old="${verilua_home_dirname}/.${verilua_home_basename}.old"
    
    # Backup old version
    if [ -d "$verilua_home_old" ]; then
        rm -rf "$verilua_home_old"
    fi
    
    mv "$VERILUA_HOME" "$verilua_home_old"
    cp -r "$dist_dir/verilua" "$VERILUA_HOME"
    
    cd "$curr_dir" || return 1
    rm -rf "$temp_dir"
    
    echo ""
    log_success "Successfully updated verilua!"
    echo ""
    log_info "New version: ${GREEN}${latest_version}${NC} ${DIM}(${latest_commit})${NC}"
    log_info "Backup location: ${DIM}${verilua_home_old}${NC}"
    echo ""
    log_warning "Please restart your shell or run: ${CYAN}source verilua.sh${NC}"
    echo ""
}

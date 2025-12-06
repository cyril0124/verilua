#!/usr/bin/env bash

set -e

# -----------------------------------------------------------------------------
# Color output utilities
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ ${NC}${1}"
}

log_success() {
    echo -e "${GREEN}✓${NC} ${1}"
}

# -----------------------------------------------------------------------------
# Install build dependencies
# -----------------------------------------------------------------------------
install_dependencies() {
    log_info "Installing build dependencies for CentOS 7..."
    
    # Use baseurl instead of mirrorlist
    sed -i s/mirror.centos.org/vault.centos.org/g /etc/yum.repos.d/*.repo
    sed -i s/^#.*baseurl=http/baseurl=http/g /etc/yum.repos.d/*.repo
    sed -i s/^mirrorlist=http/#mirrorlist=http/g /etc/yum.repos.d/*.repo
    yum clean all && yum makecache

    yum install -y centos-release-scl

    # Use baseurl instead of mirrorlist in CentOS-SCLo-scl.repo
    sed -i s/mirror.centos.org/vault.centos.org/g /etc/yum.repos.d/*.repo
    sed -i s/^#.*baseurl=http/baseurl=http/g /etc/yum.repos.d/*.repo
    sed -i s/^mirrorlist=http/#mirrorlist=http/g /etc/yum.repos.d/*.repo
    yum clean all && yum makecache

    yum install -y \
        devtoolset-11-gcc devtoolset-11-gcc-c++ devtoolset-11-make devtoolset-11-libatomic-devel \
        glibc-static libstdc++-static \
        wget curl zip unzip tar \
        autoconf automake libtool m4 \
        flex bison make \
        sqlite sqlite-devel \
        which
    
    log_success "Installed devtoolset-11"
}

# -----------------------------------------------------------------------------
# Enable modern GCC toolset
# -----------------------------------------------------------------------------
enable_gcc() {
    log_info "Enabling modern GCC toolset..."

    source /opt/rh/devtoolset-11/enable
    export PATH=/opt/rh/devtoolset-11/root/usr/bin:$PATH
    export CC=/opt/rh/devtoolset-11/root/usr/bin/gcc
    export CXX=/opt/rh/devtoolset-11/root/usr/bin/g++
    log_success "Enabled devtoolset-11 (GCC 11)"
    
    gcc --version
}


# -----------------------------------------------------------------------------
# Install Rust
# -----------------------------------------------------------------------------
install_rust() {
    log_info "Installing Rust..."
    
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH=$HOME/.cargo/bin:$PATH
    source $HOME/.cargo/env
    
    rustc --version
    cargo --version
    log_success "Rust installed"
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------
main() {
    log_info "${BOLD}Setting up CentOS 7 environment for Verilua${NC}"

    install_dependencies
    enable_gcc
    install_rust
    
    log_success "${BOLD}${GREEN}CentOS 7 environment setup completed!${NC}"
}

main

#!/bin/bash

# Install python dependency
pip install -r requirements.txt


# Install LuaJIT-2.1
source install_lua.sh


# Install lua modules
source install_lua_modules.sh


# Setup verilua home
if [ "$1" = "zsh" ]; then
    shell_rc=$HOME/.zshrc
elif [ "$1" = "bash" ]; then
    shell_rc=$HOME/.bashrc
else
    shell_rc=$HOME/.bashrc
fi

if grep -q "^[^#]*export VERILUA_HOME=" "$shell_rc"; then
    echo "VERILUA_HOME is set to $VERILUA_HOME"
else
    echo "VERILUA_HOME is not set or is empty"
    echo -e "# Verilua\nexport VERILUA_HOME=$PWD\n" >> $shell_rc
    echo "VERILUA_HOME is set to $PWD"
fi

# Setup verilua tools path
if grep -q "^[^#]*export PATH=\$VERILUA_HOME/tools:\$PATH" "$shell_rc"; then
    echo "TOOL PATH is already set"
else
    echo "TOOL PATH is not set or is empty"
    echo -e "# Verilua tool\nexport PATH=\$VERILUA_HOME/tools:\$PATH\n" >> $shell_rc
    echo "TOOL PATH is set to $PWD/tools"
fi

#!/usr/bin/env bash

# Install python dependency
python3 -m pip install -r requirements.txt


# Install LuaJIT-2.1
source install_lua.sh


# Install lua modules
source install_lua_modules.sh


# Install wave vpi
source install_wave_vpi.sh


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
    echo -e "# Activate luajit venv\nsource \$VERILUA_HOME/activate_verilua.sh\n" >> $shell_rc
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


# Install tinycc
curr_dir=$(pwd)
luajit_tcc_dir=$curr_dir/extern/luajit_tcc
cd $luajit_tcc_dir; make init; make


# Install xmake
wget https://xmake.io/shget.text -O - | bash


# Make shared lib
xmake -y

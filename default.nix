{ pkgs ? import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-24.05.tar.gz") {} }:
let
  callPackage = pkgs.callPackage;
  fetchFromGitHub = pkgs.fetchFromGitHub;

  pkgsu = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/4a793e2f3288b8f89430aab927d08d347e20b83e.tar.gz") {};
  nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/6e3fe03d595ef27048e196c71cf815425ee7171a.tar.gz") { inherit pkgs; };
  
  iverilog = callPackage ./nix/iverilog.nix {};
  
  luajit-pro = callPackage (fetchFromGitHub {
    owner = "cyril0124";
    repo = "luajit-pro";
    rev = "77abddc0ee648640371639763435bf480eb58294";
    hash = "sha256-mjayFbigYdMNbEgRthW4y+R9LvDZ4Smbv4kqJINB/FY=";
  }) {};

  luajit_tcc = callPackage (fetchFromGitHub {
    owner = "cyril0124";
    repo = "luajit_tcc";
    rev = "91034cb4a68d1af25f58c72f2598d8cfedfa054a"; # nix
    hash = "sha256-cQ3XmqhQHvh+7Q6dbhqGcYltn4UhusV5yXbvMrlgHHk=";
  }) { inherit luajit-pro; };
  
  boost_unordered = callPackage ./nix/boost_unordered.nix {};

  slang = callPackage ./nix/slang.nix {};

  wave_vpi = callPackage ./nix/wave_vpi.nix {};

  luajit_pkgs = luajit-pro.pkgs;
in pkgs.stdenv.mkDerivation rec {
  name = "verilua";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = with pkgs; [
    xmake
    unzip
    git
    cargo
  ];

  buildInputs = [
    iverilog
    luajit-pro
    luajit_tcc
    boost_unordered
    slang
    wave_vpi
  ] ++ (with pkgs; [
    # tinycc
    mimalloc
    argparse
    elfio
    sol2
    zstd # for libassert
  ]) ++ (with pkgsu; [
    boost186
    fmt_11
    inja
  ]) ++ (with nur.repos; [
    # for libassert
    foolnotion.libdwarf
    foolnotion.cpptrace
    foolnotion.libassert

  ]);

  buildPhase = ''
    xmake build -F xmake-nix.lua lua_vpi
    xmake build -F xmake-nix.lua lua_vpi_vcs

    export IVERILOG_HOME=${iverilog}
    xmake build -F xmake-nix.lua lua_vpi_iverilog
    xmake build -F xmake-nix.lua iverilog_vpi_module
    xmake build -F xmake-nix.lua vvp_wrapper

    export WAVEVPI_DIR=${wave_vpi.src}
    xmake build -F xmake-nix.lua lua_vpi_wave_vpi
    xmake build -F xmake-nix.lua wave_vpi_main

    xmake build -F xmake-nix.lua testbench_gen
  '';

  setup_verilua = pkgs.writeScriptBin "setup_verilua"
  ''
    #! ${pkgs.runtimeShell}

    show_help() {
        echo "Usage: $0 [-l verilua_home_path] [-x xmake_globaldir] [-v] [-h]"
        echo
        echo "   -l verilua_home_path   Specify the VERILUA_HOME path"
        echo "   -x xmake_globaldir     Specify the XMAKE_GLOBALDIR"
        echo "   -v                     Show version"
        echo "   -h                     Show help"
    }

    _VERILUA_HOME=${src}
    _XMAKE_GLOBALDIR=@verilua_out@

    while getopts "l:x:vh" opt; do
        case $opt in
            l )
                _VERILUA_HOME=$(realpath $OPTARG)
                echo -e "[setup_verilua] use custom VERILUA_HOME: $_VERILUA_HOME"
                ;;
            x )
                _XMAKE_GLOBALDIR=$(realpath $OPTARG)
                export XMAKE_GLOBALDIR=$_XMAKE_GLOBALDIR
                echo -e "[setup_verilua] use custom XMAKE_GLOBALDIR: $_XMAKE_GLOBALDIR"
                ;;
            v )
                echo "Version: ${version}"
                exit 0
                ;;
            h )
                show_help
                exit 0
                ;;
            \? )
                show_help
                exit 1
                ;;
        esac
    done

    export XMAKE_GLOBALDIR=$_XMAKE_GLOBALDIR # TODO: consider to remove this

    if [ -z "$XMAKE_GLOBALDIR" ]; then
        export XMAKE_GLOBALDIR=~
        mkdir -p $XMAKE_GLOBALDIR/.xmake/rules/verilua
        mkdir -p $XMAKE_GLOBALDIR/.xmake/toolchains/vcs
        mkdir -p $XMAKE_GLOBALDIR/.xmake/toolchains/wave_vpi
        cp -f @verilua_out@/.xmake/rules/verilua/xmake.lua $XMAKE_GLOBALDIR/.xmake/rules/verilua
        cp -f @verilua_out@/.xmake/toolchains/vcs/xmake.lua $XMAKE_GLOBALDIR/.xmake/toolchains/vcs
        cp -f @verilua_out@/.xmake/toolchains/wave_vpi/xmake.lua $XMAKE_GLOBALDIR/.xmake/toolchains/wave_vpi
    fi;

    export VERILUA_HOME=$_VERILUA_HOME
    export VERILUA_LIBS_HOME=@verilua_out@/lib
    export VERILUA_TOOLS_HOME=@verilua_out@/bin

    echo -e "[setup_verilua] VERILUA_HOME = $VERILUA_HOME"
    echo -e "[setup_verilua] VERILUA_LIBS_HOME = $VERILUA_LIBS_HOME"
    echo -e "[setup_verilua] VERILUA_TOOLS_HOME = $VERILUA_TOOLS_HOME"
    echo -e "[setup_verilua] XMAKE_GLOBALDIR = $XMAKE_GLOBALDIR/.xmake"
    
    export LUA_CPATH="$LUA_CPATH;${luajit_pkgs.luafilesystem.out}/lib/lua/5.1/?.so"
    export LUA_CPATH="$LUA_CPATH;${luajit_pkgs.luasocket.out}/lib/lua/5.1/?.so"
    export LUA_CPATH="$LUA_CPATH;${luajit_pkgs.linenoise.out}/lib/lua/5.1/?.so"

    export LUA_PATH="$LUA_PATH;${luajit_pkgs.penlight.out}/share/lua/5.1/?.lua"
    export LUA_PATH="$LUA_PATH;${luajit_pkgs.luasocket.out}/share/lua/5.1/?.lua"
    export LUA_PATH="$LUA_PATH;${luajit_pkgs.busted.out}/share/lua/5.1/?.lua"
    export LUA_PATH="$LUA_PATH;${luajit_pkgs.argparse.out}/share/lua/5.1/?.lua"
    export LUA_PATH="$LUA_PATH;${luajit_pkgs.inspect.out}/share/lua/5.1/?.lua"
    export LUA_PATH="$LUA_PATH;${luajit_tcc.out}/share/lua/5.1/?.lua"

    export LUA_PATH="$LUA_PATH;$VERILUA_HOME/src/gen/?.lua"
    export LUA_PATH="$LUA_PATH;$VERILUA_HOME/src/lua/verilua/?.lua"
    export LUA_PATH="$LUA_PATH;$VERILUA_HOME/src/lua/thirdparty_lib/?.lua"
    export LUA_PATH="$LUA_PATH;$VERILUA_HOME/extern/debugger.lua/?.lua"
    export LUA_PATH="$LUA_PATH;$VERILUA_HOME/extern/luafun/?.lua"
    export LUA_PATH="$LUA_PATH;$VERILUA_HOME/extern/LuaPanda/Debugger/?.lua"

    export VERILUA_EXTRA_CFLAGS="@verilua_extra_cflags@"
    export VERILUA_EXTRA_LDFLAGS="@verilua_extra_ldflags@"
    export CONFIG_TCCDIR=${pkgs.tinycc}
    export LUAJITPRO_HOME=${luajit-pro}
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp ${setup_verilua}/bin/* $out/bin
    cp ${luajit-pro}/bin/* $out/bin
    cp ${iverilog}/bin/* $out/bin
    cp tools/vvp_wrapper $out/bin/
    cp tools/wave_vpi_main $out/bin/
    cp tools/testbench_gen $out/bin/

    mkdir -p $out/.xmake
    cp -r ${src}/scripts/.xmake/* $out/.xmake

    mkdir -p $out/lib
    cp shared/liblua_vpi.so $out/lib/
    cp shared/liblua_vpi_vcs.so $out/lib/
    cp shared/liblua_vpi_iverilog.so $out/lib/
    cp shared/lua_vpi.vpi $out/lib/
    cp shared/liblua_vpi_wave_vpi.so $out/lib/

    substituteInPlace $out/bin/setup_verilua \
      --subst-var-by verilua_out $out \
      --subst-var-by verilua_extra_cflags "$NIX_CFLAGS_COMPILE" \
      --subst-var-by verilua_extra_ldflags "$NIX_LDFLAGS"
  '';
}
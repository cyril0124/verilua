{ pkgs
, stdenv
, callPackage
, fetchFromGitHub
, xmake
, unzip
, fmt
, sol2
, elfio
, mimalloc
, boost
, argparse
, zstd
, wave_vpi ? (callPackage ./wave_vpi.nix {})
, iverilog ? (callPackage ./iverilog.nix {})
, luajit-pro ? (callPackage (
    fetchFromGitHub {
      owner = "cyril0124";
      repo = "luajit-pro";
      rev = "77abddc0ee648640371639763435bf480eb58294";
      hash = "sha256-mjayFbigYdMNbEgRthW4y+R9LvDZ4Smbv4kqJINB/FY=";
    }
  ) {})
}: 
let
  boost_unordered = callPackage ./boost_unordered.nix {};
  
  nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/6e3fe03d595ef27048e196c71cf815425ee7171a.tar.gz") {
    inherit pkgs;
  };
in stdenv.mkDerivation {
  name = "lua-vpi";
  src= ./.;
  buildInputs = [
    xmake
    unzip
    fmt
    sol2
    elfio
    mimalloc
    boost
    argparse

    iverilog
    luajit-pro
    wave_vpi
    boost_unordered

    # libassert
    zstd
    nur.repos.foolnotion.libdwarf
    nur.repos.foolnotion.cpptrace
    nur.repos.foolnotion.libassert
  ];

  buildPhase = ''
    xmake b lua_vpi
    xmake b lua_vpi_vcs
    xmake b lua_vpi_wave_vpi

    export IVERILOG_HOME=${iverilog}
    xmake b lua_vpi_iverilog
    xmake b iverilog_vpi_module
    xmake b -v vvp_wrapper

    export WAVEVPI_DIR=${wave_vpi.src}
    xmake b lua_vpi_wave_vpi
    xmake b wave_vpi_main
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp shared/liblua_vpi.so $out/lib/
    cp shared/liblua_vpi_vcs.so $out/lib/
    cp shared/liblua_vpi_wave_vpi.so $out/lib/
    cp shared/liblua_vpi_iverilog.so $out/lib/
    cp shared/lua_vpi.vpi $out/lib/
    cp shared/liblua_vpi_wave_vpi.so $out/lib/
    
    mkdir -p $out/bin
    cp tools/vvp_wrapper $out/bin/
    cp tools/wave_vpi_main $out/bin/
  '';
}


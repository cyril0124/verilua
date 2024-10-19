{ pkgs ? import <nixpkgs> {}, 
  pkgsu ? import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/4a793e2f3288b8f89430aab927d08d347e20b83e.tar.gz") {} 
}: pkgsu.verilator.overrideAttrs (final: prev: {
  name = "verilator-clang";
  configureFlags = [
    "CC=${pkgs.clang_18}/bin/clang"
    "CXX=${pkgs.clang_18}/bin/clang++"
    "LINK=${pkgs.clang_18}/bin/clang++"
  ];
})
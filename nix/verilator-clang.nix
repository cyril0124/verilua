{ pkgs ? import <nixpkgs> {} }:
pkgs.verilator.overrideAttrs (final: prev: {
  name = "verilator-clang";
  configureFlags = [
    "CC=${pkgs.clang_18}/bin/clang"
    "CXX=${pkgs.clang_18}/bin/clang++"
    "LINK=${pkgs.clang_18}/bin/clang++"
  ];
})
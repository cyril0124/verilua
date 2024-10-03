{ 
  pkgs
, stdenv
, fetchFromGitHub
, callPackage
, includeTools ? false
, enableShared ? !stdenv.hostPlatform.isStatic
}:
let 
  pkgsu = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/4a793e2f3288b8f89430aab927d08d347e20b83e.tar.gz") {};
in stdenv.mkDerivation {
  pname = "slang";
  version = "6.0";
  
  src = fetchFromGitHub {
    owner = "MikePopoloski";
    repo = "slang";
    rev = "6e18236363e4f59af69d90496c3dc44a899eb6f1";
    hash = "sha256-NcYDQfy+pu+LgzYrTlVLTeeJcUho1+FaYpVaANAqdIY=";
  };

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.python3
    pkgs.ninja
  ];

  buildInputs = [
    (pkgsu.fmt_11.override { enableShared = enableShared; })
    pkgs.mimalloc
    pkgsu.boost186
  ];

  cmakeFlags = [
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DSLANG_INCLUDE_TESTS=OFF"
    "-DBUILD_SHARED_LIBS=${if enableShared then "ON" else "OFF"}"
    "-DSLANG_INCLUDE_TOOLS=${ if includeTools then "ON" else "OFF" }"
  ];
}
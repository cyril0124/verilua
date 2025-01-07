{ 
  pkgs
, stdenv
, fetchFromGitHub
, callPackage
, includeTools ? true 
, enableShared ? !stdenv.hostPlatform.isStatic
}:
let 
  pkgsu = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/4a793e2f3288b8f89430aab927d08d347e20b83e.tar.gz") {};
in stdenv.mkDerivation {
  pname = "slang";
  version = "7.0";
  
  src = fetchFromGitHub {
    owner = "cyril0124";
    repo = "slang";
    rev = "976e83b96da150130c3acec1d7b03997a2b7cd87";
    hash = "sha256-ABEzdKK/l1/NeQkjj9eFKUf6kslxpIBl8mBufeVjDrI=";
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

let
  pkgs = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/c0b1da36f7c34a7146501f684e9ebdf15d2bebf8.tar.gz") {};
  pkgsu = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/4a793e2f3288b8f89430aab927d08d347e20b83e.tar.gz") {};
in pkgs.mkShellNoCC {
  name = "verilua-dev-shell";

  packages = with pkgs; [
    which
    git
    nix
    xmake
    conan
    curl
    zip
    unzip
    pkgsu.vcpkg
    pkg-config
    # clang_18
  ];
}
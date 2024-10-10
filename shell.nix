let
  pkgs = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-24.05.tar.gz") {};
  pkgsu = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/4a793e2f3288b8f89430aab927d08d347e20b83e.tar.gz") {};
in pkgs.mkShellNoCC rec {
  name = "verilua-dev-shell";

  pacakges = with pkgs; [
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
    clang_18
  ];

  buildInputs = pacakges;
}
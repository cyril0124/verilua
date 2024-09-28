let
  pkgs = import <nixpkgs> {};

  slang = pkgs.callPackage ./slang.nix {};

  boost_unordered = pkgs.callPackage ./boost_unordered.nix {};

  nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/6e3fe03d595ef27048e196c71cf815425ee7171a.tar.gz") {
    inherit pkgs;
  };

  pkgsu = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/4a793e2f3288b8f89430aab927d08d347e20b83e.tar.gz") {};
in pkgs.mkShell {

  packages = [
    pkgs.xmake
  ];

  buildInputs = with pkgs; [
    slang
    boost_unordered

    pkgsu.fmt_11
    pkgsu.boost186
    pkgs.argparse
    pkgs.mimalloc

    # libassert
    pkgs.zstd
    nur.repos.foolnotion.libdwarf
    nur.repos.foolnotion.cpptrace
    nur.repos.foolnotion.libassert
  ];


}
let
  npinsed = import ./npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.stdenv.mkDerivation {
  name = "verilua";
  nativeBuildInputs = [
    pkgs.xmake
  ];
  # TODO: ./conanfile.py is redundant, can be removed
  buildInputs = [
    (import ./scripts/nix/slang.nix {})
    pkgs.sol2
    pkgs.argparse
    pkgs.inja
    (import ./scripts/nix/libassert.nix)
    pkgs.fmt_11
    (import ./scripts/nix/mimalloc2.nix)
    # TODO: the install_libgmp in ./xmake.lua is redundant, can be removed
    pkgs.gmp
    # TODO: Why <prj_dir>/xmake.lua rebuilds luajit_pro_helper after install luarocks?
    (import ./scripts/nix/luajit-pro)
  ];
}

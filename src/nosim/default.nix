let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.stdenv.mkDerivation rec {
  name = "nosim";
  src = ./.;
  buildInputs = [
    pkgs.fmt_11
    (import ../../scripts/nix/libassert.nix)
    pkgs.cpptrace
    (import ../../scripts/nix/libverilua.nix {simulator="nosim";})
    (import ../signal_db_gen)
  ];
  buildPhase = [
    "$CXX"
    "-std=c++20"
    "*.cpp"
    # TODO: the ../include/vpi_user.h ../include/svdpi.h is redundant, include it from verilator or other simulator.
    "-I${../include}"
    "-lfmt"
    "-lassert" "-lcpptrace"
    "-lverilua_nosim"
    "-lsignal_db_gen"
    ''-D 'VERILUA_VERSION="${pkgs.lib.trim (builtins.readFile ../../VERSION)}"' ''
    "-o" name
  ];
  installPhase = ''
    mkdir -p $out/bin
    cp ${name} $out/bin/
  '';
}

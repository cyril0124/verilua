let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.stdenv.mkDerivation rec {
  name = "wave_vpi_main";
  src = ./.;
  buildInputs = [
    pkgs.fmt_11
    pkgs.argparse
    (import ./wellen_impl)
    (import ../../scripts/nix/libverilua.nix {simulator="wave_vpi";})
  ];
  buildPhase = [
    "$CXX"
    "-std=c++20"
    "*.cpp"
    "src/control.cpp"
    "src/wave_vpi.cpp"
    "src/jit_options.cpp"
    "src/fsdb_wave_vpi.cpp"
    "src/vpi_compat_wellen.cpp"
    "-I${npinsed.boost_unordered}"
    "-I./include"
    # TODO: the ../../src/include/vpi_user.h ../../src/include/svdpi.h is redundant, include it from verilator or other simulator.
    "-I${../../src/include}"
    "-O2 -funroll-loops -fomit-frame-pointer"
    "-lfmt"
    ''-D 'VERILUA_VERSION="${pkgs.lib.trim (builtins.readFile ../../VERSION)}"' ''
    "-lwave_vpi_wellen_impl"
    "-lverilua_wave_vpi"
    "-o" name
  ];
  installPhase = ''
    mkdir -p $out/bin
    cp ${name} $out/bin/
  '';
}

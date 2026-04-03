let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.stdenv.mkDerivation rec {
  name = "cov_exporter";
  src = ./.;
  buildInputs = [
    pkgs.inja
    pkgs.sol2
    pkgs.nlohmann_json
    (import ../../scripts/nix/slang.nix {})
    pkgs.fmt_11
    (import ../../scripts/nix/mimalloc2.nix)
    (import ../../scripts/nix/libassert.nix)
    pkgs.cpptrace
    pkgs.zstd
    pkgs.libz
    # TODO: Does this luajit-pro needs withPackages?
    (import ../../scripts/nix/luajit-pro)
  ];
  # TODO: use build tool? For example Makefile.
  buildPhase = [
    "$CXX"
    # TODO: redunant?
    # "-std=c99"
    "-std=c++20"
    # TODO: ./*.cpp uses std::cerr while only include iostream
    "-include iostream"
    "*.cpp" "${npinsed.slang-common}/*.cpp"
    "-DSLANG_BOOST_SINGLE_HEADER"
    "-I${npinsed.slang-common}"
    "-I${npinsed.boost_unordered}"
    "-I./include"
    "-lsvlang" "-lfmt" "-lmimalloc"
    "-lassert" "-lcpptrace"
    # "-ldwarf"
    "-lzstd" "-lz"
    "-lluajit-5.1"
    # "-lluajit_pro_helper"
    ''-D 'VERILUA_VERSION="${pkgs.lib.trim (builtins.readFile ../../VERSION)}"' ''
    "-o" name
  ];
  installPhase = ''
    mkdir -p $out/bin
    cp ${name} $out/bin/
  '';
}

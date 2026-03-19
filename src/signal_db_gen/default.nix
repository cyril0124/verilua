let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.stdenv.mkDerivation {
  name = "signal_db_gen";
  src = ./.;
  buildInputs = [
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
  # TODO: the submodule slang-common is redunant, can be removed
  buildPhase = [
    "$CXX"
    # TODO: redunant?
    # "-std=c99"
    "-std=c++20"
    # TODO: signal_db_gen.cpp uses std::cerr while only include iostream
    "-include iostream"
    "*.cpp" "${npinsed.slang-common}/*.cpp"
    "-DSLANG_BOOST_SINGLE_HEADER"
    "-I${npinsed.slang-common}"
    "-I${npinsed.boost_unordered}"
    # TODO: <libs_dir>/include
    # TODO: <lua_dir>/include/luajit-2.1
    "-lsvlang" "-lfmt" "-lmimalloc"
    "-lassert" "-lcpptrace"
    # "-ldwarf"
    "-lzstd" "-lz"
    "-lluajit-5.1"
    # "-lluajit_pro_helper"
    ''-D 'VERILUA_VERSION="${pkgs.lib.trim (builtins.readFile ../../VERSION)}"' ''

    # TODO: is static necessary?
    # "-static"
    "-o signal_db_gen"
  ];
  installPhase = ''
    mkdir -p $out/bin
    cp signal_db_gen $out/bin/
  '';
}

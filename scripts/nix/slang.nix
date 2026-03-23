# TODO: If use nix, then ../conan/slang/ is redundant, can be removed
let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
  mimalloc2 = import ./mimalloc2.nix;
in {
  shared ? false,
}: pkgs.stdenv.mkDerivation {
  name = "svlang";
  src = builtins.fetchTarball {
    url = "https://github.com/cyril0124/slang/archive/refs/tags/v9.0.tar.gz";
    sha256 = "1bqfqf94cbf1jxj6bl4apwfqpnk5sv3kjm4s3mgxd80k4hr651j3";
  };
  # Remove the ${prefix}/ in scripts/sv-lang.pc.in, which is redundant in nix.
  # For more info, see https://github.com/NixOS/nixpkgs/issues/144170
  postPatch = ''
    sed -i 's,''${prefix}/,,' scripts/sv-lang.pc.in
  '';
  nativeBuildInputs = [
    pkgs.cmake
    pkgs.python3
  ];
  buildInputs = [
    (pkgs.fmt_11.override {enableShared = shared;})
    mimalloc2
  ];
  cmakeFlags = [
    "-DSLANG_INCLUDE_TOOLS=OFF"
    "-DSLANG_INCLUDE_TESTS=OFF"
    "-DSLANG_USE_MIMALLOC=ON"
    ''-DBUILD_SHARED_LIBS=${if shared then "ON" else "OFF"}''
  ];
}

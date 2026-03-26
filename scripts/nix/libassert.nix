let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.stdenv.mkDerivation rec {
  name = "libassert";
  src = npinsed.${name};
  nativeBuildInputs = [ pkgs.cmake ];
  buildInputs = [
    pkgs.cpptrace
    pkgs.magic-enum
    pkgs.enchant
  ];
  cmakeFlags = [
    "-DLIBASSERT_USE_EXTERNAL_CPPTRACE=ON"
    "-DLIBASSERT_USE_EXTERNAL_MAGIC_ENUM=ON"
    "-DLIBASSERT_USE_EXTERNAL_ENCHANTUM=ON"
  ];
}

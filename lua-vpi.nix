{ stdenv
, callPackage
, fetchFromGitHub
, xmake
, unzip
, fmt
, sol2
, elfio
, mimalloc
}: stdenv.mkDerivation {
  name = "lua-vpi";
  src= ./.;
  buildInputs = [
    xmake
    unzip
    fmt
    sol2
    elfio
    mimalloc

    (callPackage (
      fetchFromGitHub {
        owner = "cyril0124";
        repo = "luajit-pro";
        rev = "930b71d418dd3d495a47b9fad0c93b23ce911f3c";
        hash = "sha256-xTB5WXOL1er0gTcbsUpSknY/UorwfGsdR7sLT0gXP1k=";
      }
    ) {})
    (callPackage ./boost_unordered.nix {})
  ];

  buildPhase = ''
    xmake b lua_vpi
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp shared/liblua_vpi.so $out/lib/
  '';
}


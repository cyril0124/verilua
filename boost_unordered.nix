{ stdenv
, fetchFromGitHub
}:
stdenv.mkDerivation {
  name = "boost_unordered";
  src = fetchFromGitHub {
    owner = "MikePopoloski";
    repo = "boost_unordered";
    rev = "0c35831302a5730052582de15b31a71c2c52f1e4";
    hash = "sha256-II3LhaZTAmqn0xcWuSF01czy/IGobvpiGAgZ4EjJ6aY=";
  };
  installPhase = ''
    mkdir -p $out/include
    cp boost_unordered.hpp $out/include/
  '';
}

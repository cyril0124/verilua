{ stdenv
, fetchFromGitHub
}: 
stdenv.mkDerivation {
  name = "slang-common";
  src = fetchFromGitHub {
    owner = "cyril0124";
    repo = "slang-common";
    rev = "4f417d32909a7f01b4a8a9309e396592d8d299e9";
    hash = "sha256-4Uc5flpI7f5lADBCuJ9yyVGjL232nGo2vvlZ/NhAmLE=";
  };
  installPhase = ''
    mkdir -p $out
    cp ./* $out/
  '';
}
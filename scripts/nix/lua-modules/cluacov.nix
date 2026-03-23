{
  buildLuarocksPackage,
  fetchFromGitHub,
  luacov,
}:
buildLuarocksPackage {
  pname = "cluacov";
  version = "scm-1";
  src = fetchFromGitHub {
    owner = "mpeterv";
    repo = "cluacov";
    rev = "ca8e019e1f61b7f3f2c2d37f2728a741dc167cc5";
    hash = "sha256-+kWkLQgre80drX8QTnu15RozO4H32tboSALUTEcegsg=";
  };
  propagatedBuildInputs = [
    luacov
  ];
}


let
  pkgs = import <nixpkgs> {};
in pkgs.python3Packages.buildPythonPackage rec {
  pname = "pyslang";
  version = "6.0";
  pyproject = true;

  src = pkgs.fetchPypi {
    inherit pname version;
    hash = "sha256-CAloXqzdDCjvUWaXNa2TJE4SvQH8yMk+4ZWH5vznYMs=";
  };

  buildInputs = [
    pkgs.python3Packages.scikit-build-core
    pkgs.python3Packages.pybind11
    pkgs.python3Packages.cmake
    pkgs.python3Packages.pathspec
    pkgs.python3Packages.setuptools-scm
    pkgs.python3Packages.setuptools-scm
    pkgs.python3Packages.ninja
    pkgs.python3Packages.pyproject-metadata
    (pkgs.fmt.override {enableShared = false;})
  ];

  # only nativeBuildInputs will set CMAKE_PREFIX_PATH, which is needed during cmake's find_package
  # https://nixos.wiki/wiki/C
  nativeBuildInputs = [
    pkgs.cmake
  ];

  # don't use native cmake, use pyproject's scikit-build-core cmake
  dontUseCmakeConfigure = true;

}

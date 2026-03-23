let
  npinsed = import ../../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.rustPlatform.buildRustPackage (finalAttrs: {
  name = "luajit-pro-help";
  # TODO: The luajit2.1 submodule in luajit-pro is redundant, can be removed
  #       After removal of all submodules of luajit-pro, npinsed.luajit-pro can be fetched without submodules.
  src = npinsed.luajit-pro;
  cargoHash = "sha256-r/CAz55GYJAAk7jGwhijxRYgv5mysmhXhBlwBmdYa7I=";
})

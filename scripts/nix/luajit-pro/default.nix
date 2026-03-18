# TODO: the git submodule luajit-pro is redundant, can be removed
let
  npinsed = import ../../../npins;
  pkgs = import npinsed.nixpkgs {};
  luajit-pro = (pkgs.luajit_openresty.override {
    self = luajit-pro;
    src = npinsed.luajit2;
  }).overrideAttrs (old: {
    postPatch = ''
      cp -f ${npinsed.luajit-pro}/patch/src/* src/
      # Nix can handle the ldflags, so remove the patched one
      sed -i 's,-Wl.*target/release),,' src/Makefile
    '' + old.postPatch;
    buildFlags = [];
    buildInputs = old.buildInputs ++ [
      (import ./helper.nix)
    ];
  });
in luajit-pro

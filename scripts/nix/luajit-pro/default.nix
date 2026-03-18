# TODO: the git submodule luajit-pro is redundant, can be removed
let
  npinsed = import ../../../npins;
  pkgs = import npinsed.nixpkgs {
    # Overlay is needed because:
    # * luarocks needs lua.luaOnBuild, see <nixpkgs>/pkgs/development/tools/misc/luarocks/default.nix
    #   Noted: lua refers to lua, luajit, ...
    # * lua.luaOnBuild is luaOnBuildForHost, see <nixpkgs>/pkgs/development/interpreters/lua-5/default.nix
    # * luaOnBuildForHost is defined in <nixpkgs>/pkgs/development/interpreters/luajit/default.nix
    # * luaOnBuildForhost relies on pkgsBuildHost.${luaAttr}, where the luaAttr is luajit_2_1 here.
    # Thus, to make lua.pkgs.luarocks works, we need the overlays.
    overlays = [(final: prev: {
      # TODO: rename to luajit-pro
      luajit_2_1 = (final.luajit_openresty.override {
        self = final.luajit_2_1;
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
    })];
  };
in pkgs.luajit_2_1

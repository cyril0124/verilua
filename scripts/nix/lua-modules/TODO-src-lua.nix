# TODO: this file is redundant as we already have ./thirdparty_lib.nix and ./verilua.nix
{ lua, toLuaModule }: let
  npinsed = import ../../../npins;
  pkgs = import npinsed.nixpkgs {};
in toLuaModule (pkgs.runCommand "lua${lua.luaversion}-TODO-src-lua" {} ''
  mkdir -p $out/share/lua/${lua.luaversion}
  cp -r ${../../../src/lua}/* $out/share/lua/${lua.luaversion}
'')

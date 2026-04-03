{ lua, toLuaModule }: let
  npinsed = import ../../../npins;
  pkgs = import npinsed.nixpkgs {};
in toLuaModule (pkgs.runCommand "lua${lua.luaversion}-thirdparty_lib" {} ''
  mkdir -p $out/share/lua/${lua.luaversion}
  cp -r ${../../../src/lua/thirdparty_lib}/* $out/share/lua/${lua.luaversion}
'')

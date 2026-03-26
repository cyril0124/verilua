{
  lua,
  toLuaModule,
}:
let
  npinsed = import ../../../npins;
  pkgs = import npinsed.nixpkgs {};
in toLuaModule (pkgs.runCommand "lua${lua.luaversion}-verilua" {} ''
  mkdir -p $out/share/lua/${lua.luaversion}
  cp -r ${../../../src/lua/verilua}/* $out/share/lua/${lua.luaversion}
'')

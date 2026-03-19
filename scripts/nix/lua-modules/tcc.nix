{
  lua,
  toLuaModule,
}:
let
  npinsed = import ../../../npins;
  pkgs = import npinsed.nixpkgs {};
in toLuaModule (pkgs.runCommand "lua${lua.luaversion}-tcc" {} ''
  mkdir -p $out/share/lua/${lua.luaversion}
  cp ${npinsed.luajit_tcc}/tcc.lua $out/share/lua/${lua.luaversion}
'')

{
  buildLuarocksPackage,
}: let
  npinsed = import ../../../npins;
in buildLuarocksPackage {
  pname = "debugger-lua";
  version = "scm-1";
  src = npinsed.debugger-lua;
}

let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.symlinkJoin {
  name = "xmake-verilua-flavored";
  paths = [
    pkgs.xmake
    (pkgs.runCommand "verilua-flavors" {} ''
      mkdir -p $out/share/xmake
      cp -r ${./.}/*/ $out/share/xmake/
    '')
  ];
}

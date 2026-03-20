let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.xmake.overrideAttrs (old: {
  pname = "xmake-verilua-flavored";
  # TODO: xmake uses installdir, so symlinkJoin trick does not work.
  #       Are there any other methods that do not rebuild pkgs.xmake?
  postInstall = ''
    mkdir $out/share/xmake/rules/verilua
    cp ${./rules/verilua}/* $out/share/xmake/rules/verilua/
    for toolchain_dir in ${./toolchains}/*; do
      toolchain_name=$(basename $toolchain_dir)
      mkdir $out/share/xmake/toolchains/$toolchain_name
      cp $toolchain_dir/* $out/share/xmake/toolchains/$toolchain_name/
    done
  '';
})

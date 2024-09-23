{ xmake
, callPackage
, writeTextFile
, fetchFromGitHub

, tinycc
, python3
, fmt
, sol2
, argparse
, mimalloc
}:
let
  luajit-pro = callPackage (fetchFromGitHub {
    owner = "cyril0124";
    repo = "luajit-pro";
    rev = "77abddc0ee648640371639763435bf480eb58294";
    hash = "sha256-mjayFbigYdMNbEgRthW4y+R9LvDZ4Smbv4kqJINB/FY=";
  }) {};
  envs = writeTextFile {
    name = "envs";
    text = ''
      export VERILUA_HOME=${./.}
      export LUAJITPRO_HOME=${luajit-pro}
      export CONFIG_TCCDIR=${tinycc}
      export LUA_PATH+=";$VERILUA_HOME/src/gen/?.lua"
    '';
  };
in xmake.overrideAttrs (old: {
  postInstall = ''
    cp -r ${./scripts/xmake/rules/verilua} $out/share/xmake/rules/verilua
    cp -r ${./scripts/xmake/toolchains/vcs} $out/share/xmake/toolchains/vcs
    cp -r ${./scripts/xmake/toolchains/wave_vpi} $out/share/xmake/toolchains/wave_vpi
    cp ${envs} $out/envs
  '';
  propagatedBuildInputs = [
    (python3.withPackages (python-pkgs: [
      (import ./pyslang.nix)
    ]))

    # verilator compile needs, replacing vcpkg's job
    fmt
    sol2
    argparse

    # link verilator
    mimalloc

    (callPackage ./lua-vpi.nix {})

    # lua dependencies
    luajit-pro.pkgs.penlight
    luajit-pro.pkgs.luasocket
    # TODO: luajit-pro.pkgs.lsqlite3
    luajit-pro.pkgs.argparse
    luajit-pro.pkgs.busted
    luajit-pro.pkgs.linenoise
    luajit-pro.pkgs.luafilesystem
    (callPackage (fetchFromGitHub {
      owner = "cyril0124";
      repo = "luajit_tcc";
      rev = "91034cb4a68d1af25f58c72f2598d8cfedfa054a"; # nix
      hash = "sha256-cQ3XmqhQHvh+7Q6dbhqGcYltn4UhusV5yXbvMrlgHHk=";
    }) {
      inherit luajit-pro;
    })
    (callPackage ./luafun.nix {
      inherit luajit-pro;
    })
  ];
})

let
  npinsed = import ./npins;
  pkgs = import npinsed.nixpkgs {};
  luajit-pro = (import ./scripts/nix/luajit-pro).withPackages (luapkgs: [
    luapkgs.penlight
    luapkgs.luasocket
    luapkgs.linenoise
    luapkgs.argparse
    (luapkgs.callPackage ./scripts/nix/lua-modules/cluacov.nix {})
    (luapkgs.callPackage ./scripts/nix/lua-modules/lsqlite.nix {
      complete = false;
      nixpkgs_sqlite = pkgs.sqlite;
    })
    (luapkgs.callPackage ./scripts/nix/lua-modules/lsqlite.nix {
      complete = true;
      nixpkgs_sqlite = pkgs.sqlite;
      nixpkgs_glibc = pkgs.glibc;
    })
    (luapkgs.callPackage ./scripts/nix/lua-modules/tcc.nix {})
    (luapkgs.callPackage ./scripts/nix/lua-modules/verilua.nix {})
    # TODO: The submodule debugger.lua is redundant, can be removed
    (luapkgs.callPackage ./scripts/nix/lua-modules/debugger-lua.nix {})
  ]);
in pkgs.mkShell {
  name = "verilua";
  nativeBuildInputs = [
    (import ./scripts/.xmake)
    pkgs.verilator
  ];
  # TODO: The following dependencies are currently not used by default.nix,
  #       which means the examples can be run without these dependencies.
  #       Are these dependencies redundant?
  # TODO: ./conanfile.py is redundant, can be removed
  # buildInputs = [
  #   # TODO: the install_libgmp in ./xmake.lua is redundant, can be removed
  #   pkgs.gmp
  #   # TODO: Why <prj_dir>/xmake.lua rebuilds luajit_pro_helper after install luarocks?
  #   pkgs.tinycc
  #   (import ./src/signal_db_gen)
  #   (import ./src/dpi_exporter)
  #   (import ./src/cov_exporter)
  #   (import ./src/wave_vpi/wellen_impl)
  # ];
  buildInputs = [
    luajit-pro
    (import ./scripts/nix/libverilua.nix {simulator="verilator";})
  ];
  VERILUA_HOME = pkgs.symlinkJoin {
    name = "VERILUA_HOME";
    paths = [
      (pkgs.nix-gitignore.gitignoreSource [] ./.)
    ];
    postBuild = ''
      mkdir -p $out/tools
      ln -s ${import ./src/testbench_gen}/bin/testbench_gen $out/tools/

      ln -s ${luajit-pro}/include $out/luajit-pro/luajit2.1/
      ln -s ${luajit-pro}/lib $out/luajit-pro/luajit2.1/

      mkdir -p $out/conan_installed/include
      mkdir -p $out/conan_installed/lib

      mkdir -p $out/shared
    '';
  };
}

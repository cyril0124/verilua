let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in {
  simulator,
}: pkgs.rustPlatform.buildRustPackage {
  name = "libverilua_${simulator}";
  src = ../../libverilua;
  # TODO: separate libverilua as a standalone repo, and add a Cargo.lock for it.
  postPatch = ''
    cp ${../../Cargo.lock} ./Cargo.lock
    chmod +w ./Cargo.lock
  '';
  cargoLock.lockFile = ../../Cargo.lock;

  nativeBuildInputs = [
    pkgs.pkg-config
  ];
  buildInputs = [
    (import ./luajit-pro)
  ];
  # TODO: support other simulators
  # "verilator_i"
  # "verilator_dpi"
  # "vcs"
  # "vcs_dpi"
  # "xcelium"
  # "xcelium_dpi"
  # "iverilog"
  # "nosim"
  buildFeatures = (
    if        simulator == "verilator" then [
      "verilator" "chunk_task" "verilator_inner_step_callback"
    ] else if simulator == "wave_vpi" then [
      "wave_vpi" "chunk_task"
    ] else throw "Unknown simulator ${simulator}"
  ) ++ [
    # Common features
    "acc_time" "hierarchy_cache"
  ];
  postInstall = ''
    mv $out/lib/libverilua.so $out/lib/libverilua_${simulator}.so
  '';
}

let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.rustPlatform.buildRustPackage {
  name = "libverilua";
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
  # TODO: support other EDA tools.
  buildFeatures = [
    # Verilator features
    "chunk_task" "verilator_inner_step_callback"
    # Common features
    "acc_time" "hierarchy_cache"
  ];
}

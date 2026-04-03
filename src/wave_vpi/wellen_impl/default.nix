let
  npinsed = import ../../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.rustPlatform.buildRustPackage {
  name = "libwave_vpi_wellen_impl";
  src = ./.;
  # TODO: separate libwave_vpi_wellen_impl as a standalone repo, and add a Cargo.lock for it.
  postPatch = ''
    cp ${../../../Cargo.lock} ./Cargo.lock
    chmod +w ./Cargo.lock
  '';
  cargoLock.lockFile = ../../../Cargo.lock;

}

{ rustPlatform
, fetchFromGitHub
}: rustPlatform.buildRustPackage rec {
  name = "wave_vpi";
  
  # TODO: available when wave_vpi is open sourced
  # src = fetchFromGitHub {
  #   owner = "cyril0124";
  #   repo = "wave_vpi";
  #   rev = "991de5637a965c64720bc7c32c90e8d06ea90621";
  #   sha256 = "";
  # };
  src = ./wave_vpi;

  cargoHash = "sha256-KKAFQcP2g7LC0Pp8sLSXSMO0HS5BLNNpSbDejd4jmOk=";

  installPhase = ''
    mkdir -p $out/lib
    cp target/release/libwave_vpi_wellen_impl.so $out/lib
  '';
}
let
  npinsed = import ../../npins;
  pkgs = import npinsed.nixpkgs {};
in pkgs.mimalloc.overrideAttrs (old: {
  version = npinsed.mimalloc.version;
  src = npinsed.mimalloc;
})

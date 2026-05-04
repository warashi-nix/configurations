{
  pkgs,
  lib,
  rustPlatform,
}:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
in
rustPlatform.buildRustPackage rec {
  inherit (sources.yaskkserv2) pname version src;
  cargoLock = {
    lockFile = src + /Cargo.lock;
  };
  doCheck = false;
}

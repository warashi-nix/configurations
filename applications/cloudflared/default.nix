{ inputs, pkgs, ... }:
let
  inherit (inputs.nixpkgs-cloudflared.legacyPackages.${pkgs.stdenv.hostPlatform.system}) cloudflared;
in
{
  home.packages = [
    cloudflared
  ];
}

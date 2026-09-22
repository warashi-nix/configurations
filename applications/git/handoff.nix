{ config, pkgs, ... }:
{
  home.packages = [
    (pkgs.callPackage ./handoff/package.nix {
      inherit (config.warashi.chelly) workspaces;
    })
  ];
}

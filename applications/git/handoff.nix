{ pkgs, ... }:
{
  home.packages = [
    (pkgs.callPackage ./handoff/package.nix { })
  ];
}

{ pkgs, ... }:
let
  markmap-cli = pkgs.callPackage ./package.nix { };
in
{
  home = {
    packages = [
      markmap-cli
    ];
  };
}

{ pkgs, ... }:
let
  yaskkserv2 = pkgs.callPackage ./yaskkserv2.nix { };
in
{
  home = {
    packages = [
      yaskkserv2
    ];
  };
}

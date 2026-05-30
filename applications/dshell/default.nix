{
  config,
  inputs,
  pkgs,
  ...
}:
let
  dshell = pkgs.callPackage ./package.nix { };
in
{
  home = {
    packages = [
      dshell
    ];
  };
}

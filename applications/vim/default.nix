{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
  config = pkgs.callPackage ./config.nix { };
in
{
  config = {
    home.packages = with pkgs; [
      (pkgs.vim.overrideAttrs {
        inherit (sources.vim) src;
        version = "dev-${sources.vim.date}";
      })
    ];
    xdg = {
      configFile = {
        "vim" = {
          source = config;
          recursive = true;
        };
      };
    };
  };
}

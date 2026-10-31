{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
  config = pkgs.callPackage ./config.nix { };
  vim' = pkgs.vim.overrideAttrs {
    inherit (sources.vim) src;
    version = "dev-${sources.vim.date}-${lib.substring 0 8 sources.vim.version}";
  };
in
{
  config = {
    home.packages = [
      vim'
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

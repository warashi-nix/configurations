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
  vim-with-deps = pkgs.writeShellApplication {
    name = "vim";
    runtimeInputs = with pkgs; [
      vim'

      # keep-sorted start
      copilot-language-server
      gopls
      # keep-sorted end
    ];
    text = ''
      exec vim "$@"
    '';
  };
in
{
  config = {
    home.packages = [
      vim-with-deps
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

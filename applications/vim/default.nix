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
      nodejs_latest
      # keep-sorted end
    ];
    text = ''
      exec vim "$@"
    '';
  };
  vim-as-ime = pkgs.writeShellApplication {
    name = "vime";
    runtimeInputs = [
      vim-with-deps
      pkgs.coreutils
    ];
    text = ''
      clip="$(mktemp /tmp/clip.XXXXXX.md)"
      trap 'rm -f $clip' EXIT
      vim -c startinsert "$clip"
      if [[ -s "$clip" ]]; then
        # Remove trailing newline and copy to clipboard
        head -c -1 "$clip" | pbcopy
      fi
    '';
  };
in
{
  config = {
    home.packages = [
      vim-with-deps
    ];
    services = {
      skhd = {
        enable = pkgs.stdenv.isDarwin;
        config = ''
          meh - i : open -a Alacritty.app --args --command ${lib.getExe vim-as-ime}
          hyper - i : open -na Alacritty.app --args --command ${lib.getExe vim-as-ime}
        '';
      };
    };
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

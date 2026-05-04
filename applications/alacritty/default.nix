{
  pkgs,
  lib,
  ...
}:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
in
{
  programs.alacritty = {
    enable = true;
    theme = "modus_operandi";
    themePackage = pkgs.alacritty-theme.overrideAttrs ({
      inherit (sources.alacritty-theme) src;
      version = "0-unstable-${sources.alacritty-theme.date}";
    });
    settings = {
      env = {
        TERM = "xterm-256color";
      };
      window = {
        opacity = 1.0;
        padding = {
          x = 5;
          y = 5;
        };
      }
      // (lib.optionalAttrs pkgs.stdenv.isDarwin {
        option_as_alt = "Both";
      });
      scrolling = {
        history = 0;
      };
      font = {
        size = 15.0;
        normal = {
          family = "PlemolJP Console NF";
          style = "Light";
        };
        offset = {
          x = 2;
          y = 4;
        };
        glyph_offset = {
          x = 1;
          y = 2;
        };
      };
    };
  };
}

{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.nix;
in
{
  options.warashi.nix = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Nix options.";
    };
  };

  config = mkIf cfg.enable {
    nix = {
      enable = true;

      channel = {
        enable = false;
      };

      extraOptions = ''
        max-silent-time = 3600
      '';

      gc = {
        automatic = true;
        options = "--delete-older-than 7d";
      };

      optimise = {
        automatic = true;
      };

      settings = {
        auto-optimise-store = pkgs.stdenv.isLinux;
        experimental-features = [
          "flakes"
          "nix-command"
          "pipe-operators"
        ];
        sandbox = if pkgs.stdenv.isDarwin then "relaxed" else true;
        trusted-users = (
          [
            "root"
            "@wheel"
          ]
          ++ optional pkgs.stdenv.isDarwin "@admin"
        );
        use-xdg-base-directories = true;
        warn-dirty = false;
      };
    };
  };
}

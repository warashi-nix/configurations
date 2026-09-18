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
        auto-optimise-store = pkgs.stdenv.hostPlatform.isLinux;
        experimental-features = [
          "flakes"
          "nix-command"
          "pipe-operators"
        ];
        sandbox = if pkgs.stdenv.hostPlatform.isDarwin then "relaxed" else true;
        # flake.nix の nixConfig と同じ内容。untrusted user (chelly コンテナなど) の
        # --accept-flake-config は無視されるため、daemon 側にも持たせる。
        # cache.nixos.org は NixOS / nix-darwin のモジュールが既定で入れるので書かない。
        substituters = [
          "https://nix-community.cachix.org"
          "https://fenix.cachix.org"
          "https://warashi.cachix.org"
        ];
        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "fenix.cachix.org-1:ecJhr+RdYEdcVgUkjruiYhjbBloIEGov7bos90cZi0Q="
          "warashi.cachix.org-1:rtCm332XStmyk6/izNzI4hvpj5+14lMCIFbwEAgwAyw="
        ];
        trusted-users = (
          [
            "root"
            "@wheel"
          ]
          ++ optional pkgs.stdenv.hostPlatform.isDarwin "@admin"
        );
        use-xdg-base-directories = true;
        warn-dirty = false;
      };
    };
  };
}

{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config.warashi) username;
  cfg = config.warashi.nixos;
in
{
  config = mkIf cfg.enable {
    time.timeZone = "Asia/Tokyo";

    i18n = {
      defaultLocale = "en_US.UTF-8";
    };

    virtualisation.docker = {
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };

    programs.nix-ld = {
      enable = true;
    };

    zramSwap = {
      enable = true;
    };

    system.stateVersion = "24.11";
  };
}

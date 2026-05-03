{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.darwin;
in
{
  options.warashi.darwin = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Darwin support.";
    };
    username = mkOption {
      type = types.str;
      default = "warashi";
      description = "Username for the primary user.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.username}.home = "/Users/${cfg.username}";

    security.pam.services.sudo_local = {
      reattach = true;
      touchIdAuth = true;
      watchIdAuth = false;
    };

    system = {
      primaryUser = cfg.username;
      stateVersion = 5;
    };
  };
}

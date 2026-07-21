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
  cfg = config.warashi.darwin;
in
{
  imports = [
    # keep-sorted start
    inputs.home-manager.darwinModules.home-manager
    inputs.sops-nix.darwinModules.sops
    # keep-sorted end
  ];

  options.warashi.darwin = {
    enable = mkOption {
      type = types.bool;
      default = pkgs.stdenv.isDarwin;
      description = "Enable Darwin support.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${username}.home = "/Users/${username}";

    security.pam.services.sudo_local = {
      reattach = true;
      touchIdAuth = true;
      watchIdAuth = false;
    };

    system = {
      primaryUser = username;
      stateVersion = 5;
    };
  };
}

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
  cfg = config.warashi.homes;
in
{
  options.warashi.homes = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable warashi home-manager module for host.";
    };
  };

  config = mkIf cfg.enable {
    home-manager.users.${username} = {
      imports = [
        ../homes/${config.networking.hostname}
      ];
    };
  };
}

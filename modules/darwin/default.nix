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
  options.warashi.darwin = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Darwin support.";
    };
  };

  config = mkIf cfg.enable {
    imports = [
      ./security.nix
    ];

    users.users.${username}.home = "/Users/${username}";

    system = {
      primaryUser = username;
      stateVersion = 5;
    };
  };
}

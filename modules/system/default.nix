{
  inputs,
  options,
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  inherit (config.warashi) username;
  cfg = config.warashi.system;
in
{
  options.warashi.system = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable common system support.";
    };
    shell = mkOption {
      type = types.str;
      default = "fish";
      description = "Name of the default shell for the primary user (e.g., 'fish', 'zsh').";
    };
  };

  config = mkIf cfg.enable {
    users.users.${username} = {
      shell = pkgs.${cfg.shell};
    };

    environment.shells = [ pkgs.${cfg.shell} ];

    programs =
      if cfg.shell == "fish" then
        { fish.enable = true; }
      else if cfg.shell == "zsh" then
        { zsh.enable = true; }
      else
        { };
  };
}

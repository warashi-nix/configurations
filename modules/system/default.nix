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
  cfg = config.warashi.system;
in
{
  options.warashi.system = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable common system support.";
    };
    shell = mkOption {
      type = types.package;
      default = pkgs.fish;
      description = "Default shell for the primary user.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${username} = {
      inherit (cfg) shell;
    };

    environment.shells = [ cfg.shell ];

    programs = mkIf (programs ? "${cfg.shell.pname}") {
      "${cfg.shell.pname}".enable = true;
    };

    warashi = {
      nix = {
        enable = true;
      };
      darwin = {
        enable = pkgs.stdenv.isDarwin;
      };
    };
  };
}

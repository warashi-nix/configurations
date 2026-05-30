{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.dshell;
  dshell = pkgs.callPackage ./package.nix { };
in
{
  options.warashi.dshell = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable warashi dshell program.";
    };
    defaultConfig = mkOption {
      type = types.path;
      default = ./config/default/.devcontainer;
      description = "A path that contains devcontainer.json and devcontainer-lock.json";
    };
    overrideConfig = mkOption {
      type = types.path;
      default = ./config/override/.devcontainer;
      description = "A path that contains devcontainer.json and devcontainer-lock.json";
    };
  };
  config = mkIf cfg.enable {
    home = {
      packages = [
        dshell
      ];
    };
    xdg = {
      configFile = {
        "dshell/default" = {
          source = cfg.defaultConfig;
          recursive = true;
        };
        "dshell/override" = {
          source = cfg.overrideConfig;
          recursive = true;
        };
      };
    };
  };
}

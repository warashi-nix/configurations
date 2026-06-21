{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.warashi.chelly;
in
{
  options.warashi.chelly = {
    enable = mkOption {
      type = types.bool;
      description = "Enable Chelly options.";
      default = true;
    };
    dockerFile = mkOption {
      type = types.path;
      description = "Dockerfile for Chelly.";
      default = ./Dockerfile;
    };
    settings = mkOption {
      type = types.attrs;
      description = "Settings for Chelly.";
      default = {
        additional_mounts = [
          "chelly-nix:/nix"
          "${config.home.homeDirectory}/.copilot:/home/warashi/.copilot"
        ];
        podman_options = {
          run = [
            "--userns=keep-id"
          ];
        };
      };
    };
  };

  config = mkIf cfg.enable {
    xdg.configFile = {
      "chelly/config.toml".source = (pkgs.formats.toml { }).generate "chelly-config.toml" cfg.settings;
      "chelly/Dockerfile".source = cfg.dockerFile;
    };
  };
}

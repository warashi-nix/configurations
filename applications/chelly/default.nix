{
  pkgs,
  lib,
  config,
  inputs,
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
    package = mkOption {
      type = types.package;
      description = "Package for Chelly.";
      default = inputs.chelly.packages.${pkgs.stdenv.hostPlatform.system}.chelly;
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
          "${config.xdg.configHome}/git/ignore:/home/warashi/.config/git/ignore"
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
    home.packages = [ cfg.package ];
    xdg.configFile = {
      "chelly/config.toml".source = (pkgs.formats.toml { }).generate "chelly-config.toml" cfg.settings;
      "chelly/Dockerfile".source = cfg.dockerFile;
    };
  };
}

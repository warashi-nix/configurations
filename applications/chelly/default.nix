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
    dockerfile = mkOption {
      type = types.path;
      description = "Dockerfile for Chelly.";
      default = ./Dockerfile;
    };
    envfiles = mkOption {
      type = types.listOf types.path;
      description = "Envfile for Chelly.";
      default = [ config.sops.secrets.chelly-dotenv.path ];
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
        inherit_env = [
          "COLORTERM"
          "TERM"
          "TERM_PROGRAM"
          "TERM_PROGRAM_VERSION"
        ];
        env_files = cfg.envfiles;
        runtime_options = [
          {
            runtime = "podman";
            subcommand = "run";
            args = [
              "--userns=keep-id"
            ];
          }
          {
            runtime = "container";
            subcommand = "build";
            args = [
              "--dns=1.1.1.1"
            ];
          }
          {
            runtime = "container";
            subcommand = "run";
            args = [
              "--dns=1.1.1.1"
            ];
          }
        ];
      };
    };
  };

  config = mkIf cfg.enable {
    sops.secrets.chelly-dotenv = { };
    home.packages = [ cfg.package ];
    xdg.configFile = {
      "chelly/config.toml".source = (pkgs.formats.toml { }).generate "chelly-config.toml" cfg.settings;
      "chelly/Dockerfile".source = cfg.dockerfile;
    };
  };
}

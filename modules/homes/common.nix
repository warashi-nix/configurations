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
  config = mkIf cfg.enable {
    home-manager.users.${username} = {
      imports = [
        # keep-sorted start
        inputs.direnv-instant.homeModules.direnv-instant
        inputs.sops-nix.homeManagerModules.sops
        # keep-sorted end

        ../../applications
      ];
      programs = {
        home-manager.enable = true;
      };

      home = {
        preferXdgDirectories = true;

        sessionPath = [
          "${config.home-manager.users.${username}.home.homeDirectory}/.local/bin"
        ];

        sessionVariables = {
          EDITOR = "vim";
        };

        stateVersion = "24.11";
      };

      xdg.enable = true;
    };
  };
}

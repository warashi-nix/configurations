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
  config = mkIf cfg.enableDarwin {
    home-manager = {
      users.${username} = {
        home = {
          homeDirectory = "/Users/${username}";
          sessionPath = [
            "/opt/homebrew/bin"
          ];
        };

        targets.darwin = {
          copyApps.enable = true;
          linkApps.enable = false;
        };
      };
    };
  };
}

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
      useGlobalPkgs = true;
      useUserPackages = true;
      users.${username} = {
        home = {
          sessionPath = [
            "/opt/homebrew/bin"
          ];
        };

        targets.darwin = {
          copyApps.enable = true;
          linkApps.enable = false;
        };
      };

      backupFileExtension = "backup";

      extraSpecialArgs = {
        inherit inputs specialArgs;
      };
    };
  };
}

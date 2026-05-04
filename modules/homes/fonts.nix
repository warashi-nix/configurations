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
      fonts.fontconfig.enable = true;
      home.packages = with pkgs; [
        font-awesome
        ibm-plex
        moralerspace
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
        noto-fonts-color-emoji
        plemoljp
        plemoljp-nf
        udev-gothic
        udev-gothic-nf
      ];
    };
  };
}

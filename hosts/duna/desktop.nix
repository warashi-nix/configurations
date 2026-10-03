{ lib, pkgs, ... }:
{
  programs.niri.enable = true;

  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session.command = "${lib.getExe pkgs.tuigreet} --time --remember --cmd niri-session";
  };
}

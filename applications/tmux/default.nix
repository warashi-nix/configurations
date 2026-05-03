{
  inputs,
  pkgs,
  lib,
  ...
}:
{
  programs.tmux = {
    enable = true;
    shell = lib.getExe pkgs.fish;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    keyMode = "vi";
    mouse = true;
    shortcut = "g";
    terminal = "tmux-256color";
    sensibleOnTop = false;
    extraConfig = builtins.readFile ./extra-config.tmux;
  };
}

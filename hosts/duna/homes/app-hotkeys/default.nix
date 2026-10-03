{
  config,
  lib,
  pkgs,
  ...
}:
let
  runOrRaise = lib.getExe (pkgs.callPackage ./run-or-raise.nix { });
  ghostty = lib.getExe config.programs.ghostty.package;
in
{
  # niri は 1 ファイルに binds を 2 つ置けないので、別ファイルにして include する。
  xdg.configFile."niri/config.kdl".text = ''
    include "app-hotkeys.kdl"
  '';
  # athena の skhd と同じく、Meh (keyd が Tab の長押しに割り当てる) でアプリへ切り替える。
  xdg.configFile."niri/app-hotkeys.kdl".text = ''
    binds {
        Ctrl+Shift+Alt+E hotkey-overlay-title="Focus or Open Emacs" { spawn "${runOrRaise}" "emacs" "emacsclient" "-c"; }
        Ctrl+Shift+Alt+T hotkey-overlay-title="Focus or Open a Terminal: ghostty" { spawn "${runOrRaise}" "com.mitchellh.ghostty" "${ghostty}"; }
    }
  '';
}

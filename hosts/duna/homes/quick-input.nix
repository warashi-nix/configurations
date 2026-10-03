{ lib, pkgs, ... }:
let
  quickInput = pkgs.writeShellApplication {
    name = "quick-input";
    runtimeInputs = [ pkgs.wl-clipboard ];
    text = ''
      file=$(mktemp --suffix=.quick-input)
      trap 'rm -f "$file"' EXIT
      emacsclient -c -F '((name . "quick-input"))' "$file"
      if [ -s "$file" ]; then
        wl-copy < "$file"
      fi
    '';
  };
in
{
  # niri は 1 ファイルに binds を 2 つ置けないので、別ファイルにして include する。
  xdg.configFile."niri/config.kdl".text = ''
    include "quick-input.kdl"
  '';
  # athena で vime を呼ぶ skhd の meh+i と同じ指の動きで開けるようにする。
  xdg.configFile."niri/quick-input.kdl".text = ''
    binds {
        Ctrl+Shift+Alt+I hotkey-overlay-title="Write Japanese in Emacs" { spawn "${lib.getExe quickInput}"; }
    }

    window-rule {
        match title="^quick-input$"
        open-floating true
        default-column-width { fixed 800; }
        default-window-height { fixed 400; }
    }
  '';
}

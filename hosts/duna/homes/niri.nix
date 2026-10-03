{
  lib,
  pkgs,
  ...
}:
let
  fuzzel = lib.getExe pkgs.fuzzel;
  brightnessctl = lib.getExe pkgs.brightnessctl;
in
{
  # 既定の config.kdl を include しないのは、waybar や swaylock など入れていない
  # コマンドの spawn が残り、このファイルだけでは振る舞いが分からなくなるため。
  xdg.configFile."niri/config.kdl".text = ''
    input {
        touchpad {
            tap
            dwt
            natural-scroll
            click-method "clickfinger"
        }
    }

    output "eDP-1" {
        scale 2
    }

    prefer-no-csd

    binds {
        Mod+Shift+Slash { show-hotkey-overlay; }

        Mod+D hotkey-overlay-title="Run an Application: fuzzel" { spawn "${fuzzel}"; }

        Mod+O repeat=false { toggle-overview; }
        Mod+Q repeat=false { close-window; }

        Mod+H { focus-column-left; }
        Mod+J { focus-window-down; }
        Mod+K { focus-window-up; }
        Mod+L { focus-column-right; }
        Mod+Ctrl+H { move-column-left; }
        Mod+Ctrl+J { move-window-down; }
        Mod+Ctrl+K { move-window-up; }
        Mod+Ctrl+L { move-column-right; }

        Mod+U { focus-workspace-down; }
        Mod+I { focus-workspace-up; }
        Mod+Ctrl+U { move-column-to-workspace-down; }
        Mod+Ctrl+I { move-column-to-workspace-up; }

        Mod+BracketLeft  { consume-or-expel-window-left; }
        Mod+BracketRight { consume-or-expel-window-right; }

        Mod+R { switch-preset-column-width; }
        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }
        Mod+C { center-column; }
        Mod+Minus { set-column-width "-10%"; }
        Mod+Equal { set-column-width "+10%"; }
        Mod+V { toggle-window-floating; }
        Mod+W { toggle-column-tabbed-display; }

        XF86MonBrightnessUp allow-when-locked=true { spawn "${brightnessctl}" "--class=backlight" "set" "+10%"; }
        XF86MonBrightnessDown allow-when-locked=true { spawn "${brightnessctl}" "--class=backlight" "set" "10%-"; }

        Print { screenshot; }
        Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }
        Mod+Shift+E { quit; }
        Mod+Shift+P { power-off-monitors; }
    }
  '';
}

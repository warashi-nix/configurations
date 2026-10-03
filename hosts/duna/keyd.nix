{
  # StarLite のキーボードも外付けも BT で接続し直されるので、端末を列挙せず全キーボードに当てる。
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        # 押したまま考えて何も打たずに離したときに Esc などが出ないよう、
        # karabiner の to_if_alone の既定と同じく 1 秒を超えた単押しは捨てる。
        global.overload_tap_timeout = 1000;
        main = {
          tab = "overload(meh, tab)";
          space = "overload(shift, space)";
          capslock = "overload(control, esc)";
          leftcontrol = "overload(control, esc)";
          # Space の Shift では hjkl を大文字のまま打てるよう、矢印にするのは左 Shift だけに絞る。
          leftshift = "layer(nav)";
        };
        "meh:C-S-A" = { };
        "nav:S" = {
          h = "left";
          j = "down";
          k = "up";
          l = "right";
        };
      };
    };
  };
}

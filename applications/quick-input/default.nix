{
  config,
  lib,
  pkgs,
  ...
}:
let
  quickInput = pkgs.writeShellApplication {
    name = "quick-input";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      file=$(mktemp --suffix=.quick-input)
      trap 'rm -f "$file"' EXIT
      # GUI フレームを開くと Emacs.app が前面に来て、既存のフレームに映っているものまで見えてしまう。
      ${config.programs.emacs-twist.config.emacs}/bin/emacsclient -t "$file"
      if [ -s "$file" ]; then
        pbcopy < "$file"
      fi
    '';
  };

  columns = 60;
  lines = 8;
  margin = 16;
  inherit (config.programs.alacritty.settings) font window;
  # Alacritty は窓の大きさを桁数と行数でしか受け取らないので、右下に揃えるための幅と高さを
  # Alacritty と同じ式で求める。0.528 は PlemolJP Console の「0」の送り幅、1.175 は行の高さ(em 比)。
  placement = pkgs.writeText "quick-input-placement.js" ''
    ObjC.import("AppKit");

    function run() {
      const screen = $.NSScreen.screens.objectAtIndex(0);
      const scale = screen.backingScaleFactor;
      // winit は渡された位置を、窓を置く画面ではなく mainScreen の拡大率で論理座標に戻す。
      const positionScale = $.NSScreen.mainScreen.backingScaleFactor;
      const frame = screen.frame;
      const visible = screen.visibleFrame;
      const cellWidth = Math.floor(0.528 * ${toString font.size} * scale + ${toString font.offset.x});
      const width = (2 * Math.floor(${toString window.padding.x} * scale) + ${toString columns} * cellWidth) / scale;
      const cellHeight = Math.floor(1.175 * ${toString font.size} * scale + ${toString font.offset.y});
      const height = (2 * Math.floor(${toString window.padding.y} * scale) + ${toString lines} * cellHeight) / scale;
      const right = visible.origin.x + visible.size.width - ${toString margin};
      const bottom = frame.size.height - visible.origin.y - ${toString margin};
      // 渡した位置にはタイトルバーではなく内側の上端が来るので、タイトルバーの高さは引かない。
      return Math.round((right - width) * positionScale) + " " + Math.round((bottom - height) * positionScale);
    }
  '';
  # skhd から直接 open するのではなく、開く前に主ディスプレイの大きさから位置を決める。
  openQuickInput = pkgs.writeShellApplication {
    name = "open-quick-input";
    text = ''
      read -r x y < <(/usr/bin/osascript -l JavaScript ${placement})
      /usr/bin/open "$@" Alacritty.app --args \
        -o "window.position={x=$x,y=$y}" \
        -o "window.dimensions={columns=${toString columns},lines=${toString lines}}" \
        --command ${lib.getExe quickInput}
    '';
  };
in
{
  # Alacritty は他に使っていないので、開くとこの入力のウィンドウだけが前に出る。
  services.skhd.config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin ''
    meh - i : ${lib.getExe openQuickInput} -a
    hyper - i : ${lib.getExe openQuickInput} -na
  '';
}

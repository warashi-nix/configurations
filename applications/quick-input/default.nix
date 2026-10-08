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
  # Alacritty は窓の大きさを桁数と行数でしか受け取らないので、右端を揃えるための幅を
  # Alacritty と同じ式で求める。0.528 は PlemolJP Console の「0」の送り幅(em 比)。
  placement = pkgs.writeText "quick-input-placement.js" ''
    ObjC.import("AppKit");

    function run() {
      const screen = $.NSScreen.screens.objectAtIndex(0);
      const scale = screen.backingScaleFactor;
      const frame = screen.frame;
      const visible = screen.visibleFrame;
      const cellWidth = Math.floor(0.528 * ${toString font.size} * scale + ${toString font.offset.x});
      const width = 2 * Math.floor(${toString window.padding.x} * scale) + ${toString columns} * cellWidth;
      const right = (visible.origin.x + visible.size.width - ${toString margin}) * scale;
      const bottom = (frame.size.height - visible.origin.y - ${toString margin}) * scale;
      // winit は内側を 600 の高さで作ってから Alacritty が縮め、AppKit は下端を保って縮めるので、
      // 最終的な高さではなく 600 を引いて上端を決める。
      return Math.round(right - width) + " " + Math.round(bottom - 600 * scale);
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

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
in
{
  # Alacritty は他に使っていないので、開くとこの入力のウィンドウだけが前に出る。
  services.skhd.config = ''
    meh - i : open -a Alacritty.app --args --command ${lib.getExe quickInput}
    hyper - i : open -na Alacritty.app --args --command ${lib.getExe quickInput}
  '';
}

{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
  ghostel = inputs.my-emacs-pkgs.inputs.ghostel;
in
{
  programs.fish = {
    enable = true;
    preferAbbrs = true;
    shellAbbrs = {
      e = "emacsclient";
      g = "git";
      gt = "gitu";
      v = "vim";
      ":q" = "exit";
    };
    interactiveShellInit = ''
      # set theme and prompt
      fish_config theme choose modus
      fish_config prompt choose informative_vcs

      # 1Password Plugins
      if test -e "$HOME/.config/op/plugins.sh"
        source "$HOME/.config/op/plugins.sh"
      end

      # SSH_AUTH_SOCK
      if test -S "$SSH_AUTH_SOCK" && not test "$SSH_AUTH_SOCK" = "$HOME/.ssh/ssh_auth_sock"
        ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
      end
      if test -S "$HOME/.ssh/ssh_auth_sock"
        set -x SSH_AUTH_SOCK "$HOME/.ssh/ssh_auth_sock"
      end

      # event handler for OSC 7
      # event hander は autoload で読み込めないため、ここで定義する
      function osc7_send_pwd --on-event fish_prompt
        printf "\e]7;file://%s%s\e\\\\" (hostname) "$PWD"
      end

      if string match -q "$TERM_PROGRAM" "vscode"
        if which cursor > /dev/null 2>&1
          . (cursor --locate-shell-integration-path fish)
        else if which code > /dev/null 2>&1
          . (code --locate-shell-integration-path fish)
        end
      end

      # ghostel
      if string match -qr '^ghostel(,|$)' -- "$INSIDE_EMACS"
        source "${ghostel}/etc/shell/ghostel.fish"
      end

      ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        # ghostty shell integration
        # GHOSTTY_RESOURCES_DIR は ghostty 自体がローカル起動時にのみ子プロセスへ
        # 設定する変数で ssh 越しには引き継がれず、home-manager の
        # enableFishIntegration が生成する読み込み処理が発火しないため、
        # ssh 先でここから補う
        if test -z "$GHOSTTY_RESOURCES_DIR"; and string match -q "xterm-ghostty" -- "$TERM"
          set -gx GHOSTTY_RESOURCES_DIR "${pkgs.ghostty}/share/ghostty"
        end
      ''}
    '';
    plugins = lib.filter (x: x != null) (
      builtins.map (
        s:
        if s ? pname && s ? src then
          {
            name = s.pname;
            src = s.src;
          }
        else
          null
      ) (lib.attrsets.attrValues sources)
    );
  };
  xdg = {
    configFile = {
      "fish/themes" = {
        source = ./themes;
        recursive = true;
      };
      "fish/functions" = {
        source = ./functions;
        recursive = true;
      };
    };
  };
}

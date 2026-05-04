{ pkgs, lib, ... }:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };

  vimrc = pkgs.replaceVars ./init.vim {
    deno = "${pkgs.deno}/bin/deno";
    denops = sources.denops-vim.src;
    skkeleton = sources.skkeleton.src;
  };

  vim-as-ime = pkgs.writeShellApplication {
    name = "vime";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.vim
    ];
    text = ''
      clip="$(mktemp /tmp/clip.XXXXXX.md)"
      trap 'rm -f $clip' EXIT
      vim -u '${vimrc}' "$clip"
      if [[ -s "$clip" ]]; then
        # Remove trailing newline and copy to clipboard
        head -c -1 "$clip" | pbcopy
      fi
    '';
  };

  tmux-default-shell = pkgs.writeShellApplication {
    name = "tmux-default-shell";
    runtimeInputs = [
      pkgs.tmux
      vim-as-ime
    ];
    text = ''
      while true; do
        vime
        tmux detach-client
      done
    '';
  };

  tmux-config = pkgs.replaceVars ./tmux.conf {
    tmux_default_shell = lib.getExe tmux-default-shell;
  };

  vime-tmux-session = pkgs.writeShellApplication {
    name = "vime-tmux-session";
    runtimeInputs = [
      pkgs.tmux
    ];
    text = ''
      exec tmux -L vime-session -f '${tmux-config}' new-session -A
    '';
  };
in
{
  home.packages = [
    vim-as-ime
    vime-tmux-session
  ];
}

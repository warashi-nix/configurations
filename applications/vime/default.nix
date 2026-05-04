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
in
{
  home.packages = [
    vim-as-ime
  ];
}

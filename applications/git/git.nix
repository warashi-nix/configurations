{
  pkgs,
  config,
  lib,
  ...
}:
{
  programs.git = {
    enable = true;
    package =
      if pkgs.stdenv.isDarwin then pkgs.git.override { osxkeychainSupport = false; } else pkgs.git;
    includes = [
      { path = "~/.config/git/local"; }
    ];
    settings = {
      user = {
        name = "Shinnosuke Sawada-Dazai";
        email = "3600530+Warashi@users.noreply.github.com";
      };
      alias = {
        sw = "switch";
        sc = "switch -c";
        sch = ''! git fetch origin HEAD && git switch -c "$1" FETCH_HEAD; :'';
        delete-merged = "!git branch --merged | cut -c3- | xargs git branch -d";
        copr = "! gh pr list | fzf --tmux --accept-nth=1 | xargs --no-run-if-empty gh pr checkout --detach";
      };
      core = {
        precomposeunicode = true;
        untrackedCache = true;
        fsmonitor = false; # fsmonitor は IPC を使うので、coding agent の sandbox では動かない
      };
      push.default = "simple";
      commit = {
        verbose = true;
      };
      pull.ff = "only";
      init.defaultBranch = "main";
      fetch.prune = true;
      diff = {
        colorMoved = "default";
      };
    };
    ignores = [
      (builtins.readFile ./ignore)
    ];
    lfs = {
      enable = true;
    };
    signing = {
      format = "ssh";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/w9P7ws2J3mqoYBFbqcnIPw2idc8NYsoEF/Z3p87DL";
      signByDefault = true;
    }
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
    };
    maintenance = {
      enable = true;
    };
  };
}

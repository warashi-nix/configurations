{ pkgs, lib, ... }:
{
  # core.hooksPath は repository ごとの hook を置き換えてしまうので、config ベースの hook にする。
  programs.git.settings.hook.require-signed-push = {
    event = "pre-push";
    command = lib.getExe (pkgs.callPackage ./signed-push/package.nix { });
  };
}

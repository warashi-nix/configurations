# warashi.slack-notify の実装。本文を Slack の Incoming Webhook に POST するコマンドを、
# 使う側の module に command として渡す。
#
# URL は sops の secret slack-webhook-url から読む。別の webhook に送るホストでは、
# sops.secrets.slack-webhook-url.sopsFile などで同じ名前の secret の読み元を差し替える。
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.slack-notify;
  package = pkgs.callPackage ./package.nix { };
in
{
  options.warashi.slack-notify = {
    enable = mkEnableOption "Slack の Incoming Webhook への通知コマンド";
    command = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = [
        (getExe package)
        config.sops.secrets.slack-webhook-url.path
      ];
      description = ''
        通知コマンドの argv。続く引数か stdin を本文として送る。
        使う側は enable を立ててからこれを参照する。
      '';
    };
  };

  config = mkIf cfg.enable {
    sops.secrets.slack-webhook-url = { };
  };
}

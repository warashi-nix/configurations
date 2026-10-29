# warashi.brainium-handoff の実装。agent が brainium に書いた :handoff: 付きの依頼を
# 本人が処理するまで、locdog から Slack に通知し続ける。
#
# 本人の brainium で chelly-handoff create 済みのホストで有効にする。clone の場所と基点は
# 本人の repo の remote 設定から読む。
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.brainium-handoff;
  package = pkgs.callPackage ./package.nix { };
  notify = config.warashi.slack-notify.command;
in
{
  options.warashi.brainium-handoff = {
    enable = mkEnableOption "brainium の handoff の依頼の通知";
    repository = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/ghq/github.com/Warashi/brainium";
      description = "本人の brainium の clone。";
    };
    name = mkOption {
      type = types.str;
      default = "brainium";
      description = "chelly-handoff の handoff 名。";
    };
  };

  config = mkIf cfg.enable {
    warashi.slack-notify.enable = true;
    warashi.locdog.targets.brainium-handoff = {
      watch_cmd = [
        (getExe package)
        cfg.repository
        cfg.name
      ];
      alert_cmd = notify;
      recovery_cmd = notify ++ [ "${cfg.name} の handoff の依頼は片付いた" ];
      interval = "1m";
      # alert の stdin は直近で終わった失敗の stdout なので、threshold を interval より長くして、
      # 最初の alert までに失敗した check が 1 回は終わっているようにする。
      threshold = "90s";
      timeout = "30s";
      realert_interval = "1h";
    };
  };
}

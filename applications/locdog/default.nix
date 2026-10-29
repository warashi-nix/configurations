# warashi.locdog の実装。targets に登録された check を locdog で常駐監視する。
# check を足す module は targets に 1 本登録するだけで、locdog の起動方法は知らなくてよい。
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.locdog;
  package = inputs.locdog.packages.${pkgs.stdenv.hostPlatform.system}.default;
  program = "${package}/bin/locdog";
  command = types.listOf types.str;
  duration = mkOption {
    type = types.str;
    description = "Go の time.ParseDuration の書式 (例: 30s, 1m, 1h)。";
  };
  target = types.submodule {
    options = {
      watch_cmd = mkOption {
        type = command;
        description = "失敗 (non-zero) が threshold を超えて続くと異常とみなす。stdout は alert_cmd の stdin に渡る。";
      };
      alert_cmd = mkOption { type = command; };
      recovery_cmd = mkOption {
        type = command;
        default = [ ];
      };
      interval = duration;
      threshold = duration;
      timeout = duration;
      realert_interval = duration;
    };
  };
  configFile = config.home.file.".config/locdog/config.json".source;
in
{
  options.warashi.locdog.targets = mkOption {
    type = types.attrsOf target;
    default = { };
    description = "locdog に監視させる check。空なら locdog を動かさない。";
  };

  config = mkIf (cfg.targets != { }) (mkMerge [
    {
      # locdog は設定の置き場所を $HOME/.config に固定しているので、xdg.configHome に依らない。
      home.file.".config/locdog/config.json".text = builtins.toJSON {
        targets = mapAttrsToList (name: target: { inherit name; } // target) cfg.targets;
      };
    }
    (mkIf pkgs.stdenv.hostPlatform.isDarwin {
      launchd.agents.locdog = {
        enable = true;
        config = {
          ProgramArguments = [ program ];
          EnvironmentVariables = {
            HOME = config.home.homeDirectory;
            # locdog はこの変数を読まない。設定が変わると plist も変わり、agent が読み直される。
            LOCDOG_CONFIG = "${configFile}";
          };
          KeepAlive = true;
          RunAtLoad = true;
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/locdog.log";
        };
      };
    })
    (mkIf pkgs.stdenv.hostPlatform.isLinux {
      # 本人ユーザーは linger しているので、ログインしていなくても起動時から動く。
      systemd.user.services.locdog = {
        Unit = {
          Description = "locdog";
          X-Restart-Triggers = [ "${configFile}" ];
        };
        Service = {
          ExecStart = program;
          Restart = "always";
          # 既定の 100ms だと設定の誤りで即死を繰り返して start limit に当たり、止まったままになる。
          RestartSec = "10s";
        };
        Install.WantedBy = [ "default.target" ];
      };
    })
  ]);
}

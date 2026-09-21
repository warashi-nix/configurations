# chelly コンテナ向けの untrusted な nix-daemon 転送ソケット。
# コンテナは --userns=keep-id で動くため、本物の /nix/var/nix/daemon-socket/socket に
# つなぐと daemon からは wheel のユーザー本人に見え、trusted user として扱われる。
# trusted user は build-hook などを差し込めて実質 root なので、コンテナ内のエージェントに
# 渡すわけにはいかない。ここでは wheel に入っていない専用の system user で nix-daemon --stdio を
# 動かし、本物の daemon へ転送させる。daemon から見た接続元はその system user になるので
# untrusted に降格する。
# --stdio は非 root で動かすと store が daemon に解決されて転送モードになる
# (nix/src/nix/unix/daemon.cc の runDaemon)。念のため NIX_REMOTE で明示している。
{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.warashi.chelly-nix-proxy;
in
{
  options.warashi.chelly-nix-proxy = {
    enable = mkEnableOption "untrusted nix-daemon proxy socket for chelly containers";
    socket-dir = mkOption {
      type = types.str;
      default = "/run/chelly-nix";
      description = ''
        転送用ソケットを置くディレクトリ。コンテナはこのディレクトリを
        /nix/var/nix/daemon-socket に重ねてマウントするので、ソケットのファイル名は
        本物と同じ socket にしてある。
      '';
    };
    socket-group = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional group allowed to connect through the untrusted proxy.";
    };
  };

  config = mkIf cfg.enable {
    # DynamicUser にしないのは、Accept=yes で接続ごとにインスタンスが立つため、
    # 同時接続が別々の動的 UID を受け取って共有の StateDirectory を互いに chown し合う恐れがあるから。
    users.users.chelly-nix-proxy = {
      isSystemUser = true;
      group = "chelly-nix-proxy";
    };
    users.groups.chelly-nix-proxy = { };

    systemd.sockets.chelly-nix-proxy = {
      description = "Untrusted nix-daemon proxy socket for chelly containers";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "${cfg.socket-dir}/socket";
        Accept = true;
        SocketUser = config.warashi.username;
        SocketMode = if cfg.socket-group == null then "0600" else "0660";
        DirectoryMode = "0755";
      }
      // optionalAttrs (cfg.socket-group != null) { SocketGroup = cfg.socket-group; };
    };

    systemd.services."chelly-nix-proxy@" = {
      description = "Untrusted nix-daemon proxy for chelly containers";
      requires = [ "nix-daemon.socket" ];
      after = [ "nix-daemon.socket" ];
      environment = {
        NIX_REMOTE = "daemon";
        # nix は設定やキャッシュのために HOME を見るので、書ける場所を与えておく
        HOME = "/var/lib/chelly-nix-proxy";
      };
      serviceConfig = {
        ExecStart = "${config.nix.package}/bin/nix-daemon --stdio";
        StandardInput = "socket";
        StandardOutput = "socket";
        StandardError = "journal";
        User = "chelly-nix-proxy";
        Group = "chelly-nix-proxy";
        StateDirectory = "chelly-nix-proxy";
        # keep-sorted start
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = "AF_UNIX";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        # keep-sorted end
      };
    };
  };
}

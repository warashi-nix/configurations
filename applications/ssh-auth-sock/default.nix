{
  config,
  lib,
  pkgs,
  ...
}:
let
  sock = "${config.home.homeDirectory}/.ssh/ssh_auth_sock";

  relink = pkgs.writeShellApplication {
    name = "ssh-auth-sock-relink";
    runtimeInputs = [
      pkgs.openssh
      pkgs.coreutils
    ];
    text = ''
      shopt -s nullglob

      sock=${lib.escapeShellArg sock}

      alive() {
        [ -S "$1" ] || return 1
        # ssh-add は鍵ゼロのときも 1 を返すため、成功判定に $? -eq 0 は使わない。
        # agent へ接続できなかったときだけ 2 が返る。
        local rc=0
        SSH_AUTH_SOCK="$1" ssh-add -l >/dev/null 2>&1 || rc=$?
        [ "$rc" -ne 2 ]
      }

      if alive "$sock"; then
        exit 0
      fi

      # forwarded socket の置き場所は環境によって違うため、片方に決め打ちしない。
      # 疎通確認で弾くので、候補を広げても誤爆はしない。
      for candidate in ${lib.escapeShellArg "${config.home.homeDirectory}/.ssh/agent"}/* /tmp/ssh-*/agent.*; do
        [ -O "$candidate" ] || continue
        if alive "$candidate"; then
          ln -sfn "$candidate" "$sock"
          echo "relinked $sock -> $candidate"
          exit 0
        fi
      done

      echo "no live agent socket found; leaving $sock as is"
    '';
  };
in
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  systemd.user.services.ssh-auth-sock-relink = {
    Unit = {
      Description = "Relink ssh_auth_sock to a live SSH agent socket";
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe relink;
    };
  };

  systemd.user.timers.ssh-auth-sock-relink = {
    Unit = {
      Description = "Relink ssh_auth_sock to a live SSH agent socket";
    };
    Timer = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}

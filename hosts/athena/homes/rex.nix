{ config, lib, ... }:
let
  # 経路ごとの接続先は手元の ~/.ssh/config の Host hestia-rex / hestia-rex-warp に任せる。
  # ControlMaster を使うと、古い master が 7297 番を掴んだまま転送を張り直せなくなる。
  sshArgs = lib.escapeShellArgs [
    "-N"
    "-o"
    "ControlMaster=no"
    "-o"
    "ControlPath=none"
    "-o"
    "ExitOnForwardFailure=yes"
    "-o"
    "ConnectTimeout=3"
    "-o"
    "ServerAliveInterval=15"
    "-o"
    "ServerAliveCountMax=2"
  ];
in
{
  # Rex には SSH で接続する手段がないので、hestia の Rex の Unix socket への転送を常駐させる。
  # LAN を先に試し、つながらなければ WARP を通る。
  launchd.agents.rex-tunnel = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/usr/bin/ssh ${sshArgs} hestia-rex || exec /usr/bin/ssh ${sshArgs} hestia-rex-warp"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      # 外出先で WARP も切っているときに、接続の失敗を短い間隔で繰り返さない
      ThrottleInterval = 30;
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/rex-tunnel.log";
    };
  };
}

{ lib, pkgs, ... }:
let
  exporter = pkgs.callPackage ./package.nix { };
in
{
  # デバイスが黙ったときの開き直しは exporter 自身が 60 秒で行う。ここの watchdog と
  # Restart は、exporter のループそのものが止まったときのためのもの。
  systemd.services.ud-co2s-exporter = {
    description = "Prometheus exporter for the UD-CO2S CO2 sensor";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStart = "${lib.getExe exporter} -device /dev/ttyACM0 -listen 127.0.0.1:9126";
      WatchdogSec = "120s";
      Restart = "always";
      RestartSec = "10s";
      DynamicUser = true;
      # udev の既定の規則で /dev/ttyACM* は dialout グループになる
      SupplementaryGroups = [ "dialout" ];
    };
  };

  # Alloy は設定ディレクトリの .alloy をまとめて 1 つの設定として読むので、remote_write を共有できる。
  environment.etc."alloy/ud-co2s.alloy".text = ''
    prometheus.scrape "ud_co2s" {
      targets    = [{"__address__" = "127.0.0.1:9126", "instance" = "pi"}]
      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
    }
  '';
}

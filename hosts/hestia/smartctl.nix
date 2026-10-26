{
  # NVMe の劣化(予備領域の減少・メディアエラー・全体の摩耗)を Grafana Cloud に送る。
  # Alloy の unix exporter の nvme collector は型番などの情報だけで、SMART の値を持たない。
  # 同居する chelly の agent から読めないよう、ループバックだけで待ち受ける。
  services.prometheus.exporters.smartctl = {
    enable = true;
    listenAddress = "127.0.0.1";
    devices = [ "/dev/nvme0" ];
  };

  # Alloy は設定ディレクトリの .alloy をまとめて 1 つの設定として読むので、remote_write を共有できる。
  environment.etc."alloy/smartctl.alloy".text = ''
    prometheus.scrape "hestia_smartctl" {
      targets    = [{"__address__" = "127.0.0.1:9633", "instance" = "hestia"}]
      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
    }
  '';
}

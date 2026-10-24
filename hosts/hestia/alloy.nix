{ config, ... }:
{
  # GRAFANA_CLOUD_REMOTE_WRITE_URL / GRAFANA_CLOUD_USERNAME / GRAFANA_CLOUD_API_KEY を持つ env ファイル
  sops.secrets.hestia-grafana-cloud-env.restartUnits = [ "alloy.service" ];

  services.alloy = {
    enable = true;
    environmentFile = config.sops.secrets.hestia-grafana-cloud-env.path;
  };

  # hestia には収集と送信だけを置き、保存・画面・アラート判定は Grafana Cloud 側に任せる。
  # collector は温度・周波数・電力・負荷に絞る。node_exporter の既定一式だと、
  # Free の 10k 系列を無駄に使う。
  # rapl は実機で collector_success が 0 だった。energy_uj が root 専用なのが原因とみられる。
  # 読めるよう緩めると、chelly の agent など同居する非特権のコードが電力の副チャネル
  # (PLATYPUS)を読めてしまうので、CPU の電力は取らない。
  environment.etc."alloy/config.alloy".text = ''
    prometheus.exporter.unix "hestia" {
      set_collectors = [
        "hwmon",
        "thermal_zone",
        "cpufreq",
        "nvme",
        "drm",
        "cpu",
        "loadavg",
        "meminfo",
        "pressure",
      ]
    }

    prometheus.scrape "hestia" {
      targets    = prometheus.exporter.unix.hestia.targets
      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
      job_name   = "hestia"
    }

    prometheus.remote_write "grafana_cloud" {
      endpoint {
        url = sys.env("GRAFANA_CLOUD_REMOTE_WRITE_URL")

        basic_auth {
          username = sys.env("GRAFANA_CLOUD_USERNAME")
          password = sys.env("GRAFANA_CLOUD_API_KEY")
        }
      }
    }
  '';
}

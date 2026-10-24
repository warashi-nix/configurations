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
  environment.etc."alloy/config.alloy".text = ''
    prometheus.exporter.unix "hestia" {
      set_collectors = [
        "hwmon",
        "thermal_zone",
        "cpufreq",
        "rapl",
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

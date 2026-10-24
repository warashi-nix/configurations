{ config, ... }:
{
  # GRAFANA_CLOUD_REMOTE_WRITE_URL / GRAFANA_CLOUD_USERNAME / GRAFANA_CLOUD_API_KEY を持つ env ファイル
  sops.secrets.hestia-grafana-cloud-env.restartUnits = [ "alloy.service" ];

  services.alloy = {
    enable = true;
    environmentFile = config.sops.secrets.hestia-grafana-cloud-env.path;
  };

  # hestia には収集と送信だけを置き、保存・画面・アラート判定は Grafana Cloud 側に任せる。
  # collector は温度・周波数・電力と、その裏付けになる負荷・IO に絞る。node_exporter の
  # 既定一式だと、Free の 10k 系列を無駄に使う。
  # rapl は実機で collector_success が 0 だった。energy_uj が root 専用なのが原因とみられる。
  # 読めるよう緩めると、chelly の agent など同居する非特権のコードが電力の副チャネル
  # (PLATYPUS)を読めてしまうので、CPU の電力は取らない。
  # プロセスは「ユーザー名:実行ファイル名」で束ねる。n8n と chelly の agent はどちらも node で
  # 動くので、実行ファイル名だけだと区別できない。smaps とスレッド単位は CPU と系列数が
  # 増えるわりに、切り分けには要らないので切る。
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
        "diskstats",
        "netdev",
        "filesystem",
        "stat",
        "vmstat",
      ]
    }

    prometheus.scrape "hestia" {
      targets    = prometheus.exporter.unix.hestia.targets
      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
    }

    prometheus.exporter.process "hestia" {
      gather_smaps        = false
      track_threads       = false
      remove_empty_groups = true

      matcher {
        name    = "{{.Username}}:{{.Comm}}"
        cmdline = [".+"]
      }
    }

    prometheus.scrape "hestia_process" {
      targets    = prometheus.exporter.process.hestia.targets
      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
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

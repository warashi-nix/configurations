{ config, ... }:
{
  # GRAFANA_CLOUD_REMOTE_WRITE_URL / GRAFANA_CLOUD_USERNAME / GRAFANA_CLOUD_API_KEY を持つ env ファイル
  sops.secrets.hestia-grafana-cloud-env.restartUnits = [ "alloy.service" ];

  services.alloy = {
    enable = true;
    environmentFile = config.sops.secrets.hestia-grafana-cloud-env.path;
  };

  # chelly の Lean などがメモリを使い切ってホスト全体が詰まると、Alloy のページが追い出されて
  # メトリクスが途切れる(2026-10-25 に 10 分)。cgroup v2 の保護は祖先にも同じ設定が要るので、
  # system.slice にも置く。MemoryLow はベストエフォートで、詰まりそのものは防がない。
  systemd.services.alloy.serviceConfig.MemoryLow = "300M";
  systemd.slices.system = {
    # system.slice は systemd が暗黙に作るので、unit を丸ごと置かずにドロップインで足す
    overrideStrategy = "asDropin";
    # 実測で system.slice は 1.1G(nix-daemon 444M、alloy 160M、datadog 94M、n8n 91M、journald 84M)。
    # 子が MemoryLow を持たない分は奪い合いになるので、全体が収まる大きさにする。
    sliceConfig.MemoryLow = "1536M";
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

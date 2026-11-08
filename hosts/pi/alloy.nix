{ config, ... }:
{
  # GRAFANA_CLOUD_REMOTE_WRITE_URL / GRAFANA_CLOUD_USERNAME / GRAFANA_CLOUD_API_KEY を持つ env ファイル。
  # Pi だけ失効できるよう、hestia とは別のキーにする。
  sops.secrets.pi-grafana-cloud-env.restartUnits = [ "alloy.service" ];

  services.alloy = {
    enable = true;
    environmentFile = config.sops.secrets.pi-grafana-cloud-env.path;
  };

  # Pi には収集と送信だけを置き、保存・画面・アラート判定は Grafana Cloud 側に任せる。
  # 何を集めるかは、集める側のモジュールが自分の .alloy ファイルで足す。
  environment.etc."alloy/config.alloy".text = ''
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

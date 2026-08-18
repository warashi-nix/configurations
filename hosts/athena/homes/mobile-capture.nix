{ config, ... }:
{
  # consumer token は pull と ack ができてしまうため、iOS ショートカットが持つ
  # producer token と違って athena だけに配る。
  sops.secrets.mobile-capture-consumer-token = {
    path = "${config.xdg.configHome}/mobile-capture/consumer-token";
  };
}

{
  # IP の設定は systemd-networkd の 99-wireless-client-dhcp に任せ、iwd は接続の管理だけを担う。
  networking.wireless.iwd = {
    enable = true;
    settings.General.EnableNetworkConfiguration = false;
  };
}

{
  networking.hostName = "pi";
  # systemd-networkd に替えると DHCP のクライアント ID が変わり、athena から繋ぐ
  # 192.168.10.6 が変わりうるので、旧設定と同じ NetworkManager に留める。
  networking.networkmanager.enable = true;

  security.pam = {
    rssh.enable = true;
    services = {
      sudo = {
        rssh = true;
      };
    };
  };

  # 全ホスト共通の home-manager は emacs などを入れるので、CO2 の監視だけの Pi では切る
  warashi.homes.enable = false;
}

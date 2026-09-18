{
  # chelly コンテナにホストの nix store を共有するための転送ソケット。
  # homes/chelly.nix 側の nix-store = "host" と対になる。
  warashi.chelly-nix-proxy.enable = true;
}

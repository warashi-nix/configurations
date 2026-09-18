{
  warashi.chelly = {
    uid = 1000;
    gid = 100;

    # workbench は NixOS なのでホストの store をそのまま使い、volume への再取得を避ける。
    # 対になる転送ソケットは ../chelly.nix で有効にしている。
    nix-store = "host";
  };
}

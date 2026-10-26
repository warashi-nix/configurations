{
  warashi.chelly = {
    uid = 1000;
    gid = 100;

    # hestia は NixOS なのでホストの store をそのまま使い、volume への再取得を避ける。
    # 対になる転送ソケットは ../chelly.nix で有効にしている。
    nixStore = "host";

    # コンテナの /tmp への書き込みを NVMe に届かせない。tmpfs はコンテナの --memory に含まれるので、
    # 使い切って OOM になる前に容量不足で止まるよう size を付ける。podman の既定の noexec は
    # go test などが /tmp に置いた実行ファイルを動かせなくするので exec にする。
    runtime_options.podman.run = [
      "--tmpfs=/tmp:rw,exec,nosuid,nodev,size=4g,mode=1777"
    ];
  };
}

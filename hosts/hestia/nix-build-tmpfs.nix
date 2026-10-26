{
  # nix のビルドの一時ディレクトリ(build-dir 未設定時の既定)をメモリに置き、NVMe への書き込みを減らす。
  # tmpfs のページは書いたビルドの cgroup に課金されるので、slice の上限でビルドの実メモリと合わせて抑える。
  # 上限を超える大きなビルドは容量不足で失敗するのを許す。
  fileSystems."/nix/var/nix/builds" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "size=8G"
      "mode=0755"
    ];
  };

  # agent の nix build は nix-daemon で動き、コンテナの 8G が効かないので、ここで上限を持つ。
  systemd.slices.nixbuild.sliceConfig.MemoryMax = "12G";
}

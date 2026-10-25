{
  # chelly-agent のビルドも nix-daemon で動くので、コンテナの CPU 上限の外にある。
  # use-cgroups が無効でビルドは nix-daemon.service の cgroup に入るため、この unit を動かせば足りる。
  # system.slice の中で重みを下げても、agent のいる user.slice には譲らないので、
  # ルート直下の兄弟にして agent と同程度の低さにする。
  # CPUWeight=idle はコンテナが CPU を使い切る間ビルドが止まるので採らない。
  systemd.slices.nix-build.sliceConfig.CPUWeight = 20;
  systemd.services.nix-daemon.serviceConfig.Slice = "nix-build.slice";
  nix.daemonCPUSchedPolicy = "batch";
}

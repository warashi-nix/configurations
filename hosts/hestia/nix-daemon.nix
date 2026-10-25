{
  # chelly-agent のビルドも nix-daemon で動くので、コンテナの CPU 上限の外にある。
  # use-cgroups が無効でビルドは nix-daemon.service の cgroup に入るため、ここに重みを置けば足りる。
  # CPUWeight=idle はコンテナが CPU を使い切る間ビルドが止まるので採らない。
  nix.daemonCPUSchedPolicy = "batch";
  systemd.services.nix-daemon.serviceConfig.CPUWeight = 20;
}

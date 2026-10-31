{
  config,
  lib,
  ...
}:
{
  # chelly コンテナにホストの nix store を共有するための転送ソケット。
  # homes/chelly.nix 側の nixStore = "host" と対になる。
  warashi.chelly-nix-proxy.enable = true;
  warashi.chelly-agent = {
    enable = true;
    envfiles = lib.mkIf config.warashi.chelly-agent.enable [
      config.sops.secrets.chelly-agent-dotenv.path
    ];
    # コンテナの /tmp への書き込みを NVMe に届かせない。tmpfs はコンテナの --memory に含まれるので、
    # 使い切って OOM になる前に容量不足で止まるよう size を付ける。podman の既定の noexec は
    # go test などが /tmp に置いた実行ファイルを動かせなくするので exec にする。
    runArgs = [
      "--tmpfs=/tmp:rw,exec,nosuid,nodev,size=4g,mode=1777"
    ];
  };
  # 複数の agent が同時に動くと、コンテナごとの CPU 上限の合計がコア数を超える。
  # slice 名に uid が要るので、既に割り当てられている値で固定する。workbench の uid は
  # 異なりうるため、モジュールには置かない。
  users.users.chelly-agent.uid = 999;
  systemd.slices."user-999" = {
    # user-999.slice は logind が user-.slice から作るので、ドロップインで足す
    overrideStrategy = "asDropin";
    sliceConfig.CPUWeight = 20;
  };
  sops.secrets = lib.mkIf config.warashi.chelly-agent.enable {
    chelly-agent-dotenv = {
      owner = "chelly-agent";
      group = "chelly-agent";
      mode = "0400";
    };
  };
}

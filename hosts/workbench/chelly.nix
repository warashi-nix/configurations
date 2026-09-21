{
  config,
  lib,
  ...
}:
{
  # chelly コンテナにホストの nix store を共有するための転送ソケット。
  # homes/chelly.nix 側の nix-store = "host" と対になる。
  warashi.chelly-nix-proxy.enable = true;
  warashi.chelly-agent = {
    enable = true;
    envfiles = lib.mkIf config.warashi.chelly-agent.enable [
      config.sops.secrets.chelly-agent-dotenv.path
    ];
  };
  sops.secrets = lib.mkIf config.warashi.chelly-agent.enable {
    chelly-agent-dotenv = {
      owner = "chelly-agent";
      group = "chelly-agent";
      mode = "0400";
    };
  };
}

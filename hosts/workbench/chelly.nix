{
  config,
  lib,
  ...
}:
{
  # chelly-agent のコンテナにホストの nix store を共有するための転送ソケット。
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

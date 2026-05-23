{ config, pkgs, ... }:
{
  sops.secrets.cloudflared-creds = { };
  services.cloudflared = {
    enable = true;
    tunnels = {
      "393c3895-c017-4ae2-9eb9-dc0c21fa1e54" = {
        credentialsFile = config.sops.secrets.cloudflared-creds.path;
        default = "http_status:404";
      };
    };
  };
}

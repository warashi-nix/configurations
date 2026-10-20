{ config, ... }:
{
  sops.secrets.hestia-cloudflared-creds = { };
  services.cloudflared = {
    enable = true;
    tunnels = {
      "83c26919-e6f6-47ab-b1d5-f4cb6d5480e1" = {
        credentialsFile = config.sops.secrets.hestia-cloudflared-creds.path;
        default = "http_status:404";
      };
    };
  };
}

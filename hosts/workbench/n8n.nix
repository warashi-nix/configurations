{
  services.n8n = {
    enable = true;
    openFirewall = true;
    environment = {
      WEBHOOK_URL = "https://n8n.taileef3.ts.net/";
    };
  };
}

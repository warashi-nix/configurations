{
  services.n8n = {
    enable = true;
    openFirewall = false;
    environment = {
      WEBHOOK_URL = "https://n8n.warashi.dev/";
    };
  };
}

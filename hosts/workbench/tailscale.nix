{
  services.tailscale = {
    serve = {
      enable = true;
      services = {
        n8n = {
          endpoints = {
            "tcp:443" = "http://localhost:5678";
          };
        };
      };
    };
  };
}

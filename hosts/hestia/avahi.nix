{
  services.avahi = {
    enable = true;
    settings = {
      publish = {
        publish-addresses = true;
        disable-publishing = false;
      };
    };
  };
}

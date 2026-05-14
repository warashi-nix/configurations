{
  time.timeZone = "Asia/Tokyo";

  i18n = {
    defaultLocale = "en_US.UTF-8";
  };

  virtualisation.docker = {
    enable = true;
  };

  programs.nix-ld = {
    enable = true;
  };

  zramSwap = {
    enable = true;
  };

  system.stateVersion = "24.11";
}

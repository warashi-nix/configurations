{ pkgs, ... }:
{
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.tmp = {
    useTmpfs = true;
  };

  networking.hostName = "hestia";
  networking.useNetworkd = true;
  systemd.network.enable = true;
  security.pam = {
    rssh.enable = true;
    services = {
      sudo = {
        rssh = true;
      };
    };
  };
}

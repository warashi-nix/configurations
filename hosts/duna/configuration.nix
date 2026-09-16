{
  pkgs,
  ...
}:
{
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.tmp = {
    useTmpfs = true;
  };

  networking.hostName = "duna";
  networking.useNetworkd = true;
  systemd.network.enable = true;
}

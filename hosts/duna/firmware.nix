{
  services.fwupd = {
    enable = true;
    # Secure Boot is disabled, so dbx updates have no effect.
    daemonSettings.DisabledPlugins = [ "uefi_dbx" ];
  };
}

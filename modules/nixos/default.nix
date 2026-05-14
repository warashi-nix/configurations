{ inputs, config, ... }:
let
  inherit (config.warashi) username;
in
{
  imports = [
    # keep-sorted start
    inputs.disko.nixosModules.disko
    inputs.home-manager.darwinModules.home-manager
    inputs.sops-nix.nixosModules.sops
    # keep-sorted end
  ];

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

  users = {
    mutableUsers = false;

    users.${username} = {
      home = "/home/${username}";
      isNormalUser = true;
      linger = true;
      autoSubUidGidRange = true;
      hashedPasswordFile =
        if config.sops.secrets ? login-password then config.sops.secrets.login-password.path else null;
      extraGroups = [
        "wheel"
        "networkmanager"
        "docker"
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/w9P7ws2J3mqoYBFbqcnIPw2idc8NYsoEF/Z3p87DL"
      ];
    };
  };

  sops.secrets.login-password.neededForUsers = true;

  system.stateVersion = "24.11";
}

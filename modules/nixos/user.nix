{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config.warashi) username;
  cfg = config.warashi.nixos;
in
{
  config = mkIf cfg.enable {
    users = {
      mutableUsers = false;

      users.${username} = {
        home = "/home/${username}";
        isNormalUser = true;
        linger = true;
        # autoSubUidGidRange は 65536 個固定で、--userns=keep-id なコンテナ内の
        # useradd が要求する subuid (100000 + 65536) を収容できないため明示指定する
        autoSubUidGidRange = false;
        subUidRanges = [
          {
            startUid = 100000;
            count = 196608;
          }
        ];
        subGidRanges = [
          {
            startGid = 100000;
            count = 196608;
          }
        ];
        hashedPasswordFile =
          if config.sops.secrets ? login-password then config.sops.secrets.login-password.path else null;
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/w9P7ws2J3mqoYBFbqcnIPw2idc8NYsoEF/Z3p87DL"
        ];
      };
    };

    sops.secrets.login-password.neededForUsers = true;
  };
}

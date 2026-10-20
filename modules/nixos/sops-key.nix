{ config, lib, ... }:
let
  inherit (config.warashi) username;
  cfg = config.warashi.nixos;
  owner = "${username} ${config.users.users.${username}.group}";
in
{
  # home-manager の sops はログインユーザーの権限で system と同じ鍵を読むので、
  # root 専用にはできない。chelly-agent など他のユーザーには読ませない。
  # 鍵の生成は最初の 1 回だけで書き込みは要らないため、write も落とす。
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "z /var/lib/sops-nix 0500 ${owner} - -"
      "z /var/lib/sops-nix/key.txt 0400 ${owner} - -"
    ];
  };
}

{ config, lib, ... }:
let
  inherit (config.warashi) username;
  cfg = config.warashi.nixos;
  user = "${username} ${config.users.users.${username}.group}";
in
{
  # home-manager の sops はログインユーザーの権限で system と同じ鍵を読むので、
  # root 専用にはできない。chelly-agent など他のユーザーには読ませない。
  # 鍵の生成は最初の 1 回だけで書き込みは要らないため、write も落とす。
  # ディレクトリをログインユーザー所有にすると、root 所有の key.txt が
  # systemd-tmpfiles に unsafe path transition として拒否されるので root に残す。
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "z /var/lib/sops-nix 0555 root root - -"
      "z /var/lib/sops-nix/key.txt 0400 ${user} - -"
    ];
  };
}

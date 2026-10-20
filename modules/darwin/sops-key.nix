{ config, lib, ... }:
let
  inherit (config.warashi) username;
  cfg = config.warashi.darwin;
in
{
  # home-manager の sops はログインユーザーの権限で system と同じ鍵を読む。
  # 鍵の生成は最初の 1 回だけで書き込みは要らないため、write も落とす。
  config = lib.mkIf cfg.enable {
    system.activationScripts.postActivation.text = ''
      if [ -e /var/lib/sops-nix/key.txt ]; then
        chown ${username} /var/lib/sops-nix /var/lib/sops-nix/key.txt
        chmod 0500 /var/lib/sops-nix
        chmod 0400 /var/lib/sops-nix/key.txt
      fi
    '';
  };
}

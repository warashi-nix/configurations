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
  cfg = config.warashi.sops;
  sops = {
    defaultSopsFile = ../../secrets/default.yaml;
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
    };
  };
in
{
  options.warashi.sops = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable sops options.";
    };
  };

  config = mkIf cfg.enable {
    inherit sops;

    # home-manager の sops モジュールは warashi.homes が有効なときだけ import される
    home-manager.users.${username} = mkIf config.warashi.homes.enable {
      sops = sops // {
        secrets = {
          age-public-key = {
            path = "${config.home-manager.users.${username}.xdg.configHome}/age/public-key";
          };
          age-secret-key = {
            path = "${config.home-manager.users.${username}.xdg.configHome}/age/secret-key";
          };
        };
      };
    };
  };
}

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
  cfg = config.warashi.darwin;
in
{
  imports = [
    # keep-sorted start
    inputs.home-manager.darwinModules.home-manager
    inputs.sops-nix.darwinModules.sops
    # keep-sorted end
  ];

  options.warashi.darwin = {
    enable = mkOption {
      type = types.bool;
      default = pkgs.stdenv.isDarwin;
      description = "Enable Darwin support.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${username}.home = "/Users/${username}";

    security.pam.services.sudo_local = {
      reattach = true;
      touchIdAuth = true;
      watchIdAuth = false;
    };

    environment = {
      systemPath = lib.mkForce (
        [
          # save the original PATH for use in the shell profile
          "\${PATH}\${PATH:+:}${(makeBinPath config.environment.profiles)}"
        ]
        ++ [ "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" ]
      );
      extraInit = ''
        # Remove duplicate entries from PATH while preserving order, leaving the last occurrence of each entry.
        PATH=$(printf '%s' "$PATH" | awk -v RS=: -v ORS=: '{a[NR]=$0; last[$0]=NR} END {for (i=1; i<=NR; i++) if (last[a[i]]==i) print a[i]}' | sed 's/:$//')
      '';
    };

    system = {
      primaryUser = username;
      stateVersion = 5;
    };
  };
}

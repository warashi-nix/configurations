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
  cfg = config.warashi.homes;
in
{
  options.warashi.homes = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable warashi home-manager module.";
    };
    enableDarwin = mkOption {
      type = types.bool;
      default = pkgs.stdenv.isDarwin;
      description = "Enable home-manager on darwin.";
    };
  };
}

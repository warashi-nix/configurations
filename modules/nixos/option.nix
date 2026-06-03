{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.nixos;
in
{
  options.warashi.nixos = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable warashi nixos module.";
    };
  };
}

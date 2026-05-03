{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.nixpkgs;
in
{
  options.warashi.nixpkgs = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable nixpkgs options.";
    };
    overlays = mkOption {
      type = types.listOf (
        lib.mkOptionType {
          name = "nixpkgs-overlay";
          description = "nixpkgs overlay";
          check = lib.isFunction;
          merge = lib.mergeOneOption;
        }
      );
      default = [ ];
      description = "List of paths to nixpkgs overlays.";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs = {
      inherit (cfg) overlays;
      config = {
        allowUnfree = true;
      };
    };
  };
}

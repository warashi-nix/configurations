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
    enable = mkEnableOption "";
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
    nixpgks = {
      inherit (cfg) overlays;
      config = {
        allowUnfree = true;
      };
    };
  };
}

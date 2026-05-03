{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi;
in
{
  options.warashi = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Warashi configuration.";
    };
    username = mkOption {
      type = types.str;
      default = "warashi";
      description = "Username for Primary user.";
    };
  };

  config = mkIf cfg.enable {
    imports = (
      builtins.map (modules: ./. + "/${modules}") (
        builtins.filter (x: x != "default.nix") (builtins.attrNames (builtins.readDir ./.))
      )
    );
  };
}

{
  platform,
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi;
  shouldImportModule = x: x != "default.nix" && (x == platform || (x != "nixos" && x != "darwin"));
in
{
  imports = (
    builtins.map (module: ./. + "/${module}") (
      builtins.filter shouldImportModule (builtins.attrNames (builtins.readDir ./.))
    )
  );

  options.warashi = {
    username = mkOption {
      type = types.str;
      default = "warashi";
      description = "Username for Primary user.";
    };
  };
}

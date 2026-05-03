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
  imports = (
    builtins.map (module: ./. + "/${module}") (
      builtins.filter (x: x != "default.nix") (builtins.attrNames (builtins.readDir ./.))
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

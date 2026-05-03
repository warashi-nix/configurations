{ lib, ... }:
{
  imports = (
    builtins.map (module: ./. + "/${module}") (
      builtins.filter (x: x != "default.nix" && lib.strings.hasSuffix ".nix" x) (
        builtins.attrNames (builtins.readDir ./.)
      )
    )
  );
}

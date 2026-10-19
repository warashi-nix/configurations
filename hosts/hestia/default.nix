{
  imports = (
    builtins.map (module: ./. + "/${module}") (
      builtins.filter (x: x != "default.nix" && x != "facter.json") (
        builtins.attrNames (builtins.readDir ./.)
      )
    )
  );
}

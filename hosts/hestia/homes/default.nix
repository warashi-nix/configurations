{
  config,
  ...
}:
let
  inherit (config.warashi) username;
in
{
  home-manager.users.${username} = {
    imports = (
      builtins.map (module: ./. + "/${module}") (
        builtins.filter (x: x != "default.nix") (builtins.attrNames (builtins.readDir ./.))
      )
    );
  };
}

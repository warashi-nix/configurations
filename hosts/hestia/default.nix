let
  entries = builtins.readDir ./.;
  # .nix 以外のファイル(ダッシュボードの JSON など)は import しない
  isModule =
    name:
    name != "default.nix" && (entries.${name} == "directory" || builtins.match ".*\\.nix" name != null);
in
{
  imports = builtins.map (module: ./. + "/${module}") (
    builtins.filter isModule (builtins.attrNames entries)
  );
}

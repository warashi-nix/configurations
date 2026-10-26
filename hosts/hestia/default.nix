let
  entries = builtins.readDir ./.;
  # .nix 以外のファイル(ダッシュボードの JSON など)と、default.nix を持たないディレクトリ
  # (アラートルールなど)は import しない
  isModule =
    name:
    name != "default.nix"
    && (
      if entries.${name} == "directory" then
        builtins.pathExists (./. + "/${name}/default.nix")
      else
        builtins.match ".*\\.nix" name != null
    );
in
{
  imports = builtins.map (module: ./. + "/${module}") (
    builtins.filter isModule (builtins.attrNames entries)
  );
}

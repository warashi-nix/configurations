{
  callPackage,
  replaceVarsWith,
  symlinkJoin,
  deno,
  lib,
  ...
}:
let
  plugins = callPackage ./plugins { };

  replaced-vars = {
    deno = lib.getExe' deno "deno";
    merged_plugins = plugins;
  };

  matchAllPlaceholders =
    string:
    let
      r = builtins.match "[^@]*@([a-zA-Z_][0-9A-Za-z_'-]*)@(.*)" string;
      result = if r == null then [ ] else lib.lists.take ((builtins.length r) - 1) r;
      rest = if r == null then "" else builtins.elemAt (lib.lists.drop ((builtins.length r) - 1) r) 0;
    in
    result ++ (if (builtins.length result) > 0 then (matchAllPlaceholders rest) else [ ]);

  replaceVars =
    fromPath: toDir:
    replaceVarsWith {
      src = fromPath;
      replacements =
        let
          exist-patterns = matchAllPlaceholders (builtins.readFile fromPath);
        in
        lib.attrsets.filterAttrs (
          n: _: if exist-patterns == null then false else (builtins.elem n exist-patterns)
        ) replaced-vars;
      dir = toDir;
      ieExecutable = false;
    };

in
symlinkJoin {
  name = "vim-config";
  paths = builtins.map (
    path: replaceVars path (builtins.dirOf (lib.path.removePrefix ./config path))
  ) (lib.filesystem.listFilesRecursive ./config);
}

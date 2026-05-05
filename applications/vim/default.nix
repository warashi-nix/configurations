{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
  lnsyncJoin = pkgs.callPackage ./lnsync-join { };

  replaced-vars = {
    deno = lib.getExe' pkgs.deno "deno";
    merged_plugins = lnsyncJoin {
      name = "vim-plugins";
      paths = lib.filter (x: x != null) (
        builtins.map (s: if s ? src then s.src else null) (lib.attrsets.attrValues sources)
      );
      postBuild = ''
        rm -f $out/deno.json $out/deno.jsonc
      '';
    };
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
    pkgs.replaceVarsWith {
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

  config = pkgs.symlinkJoin {
    name = "vim-config";
    paths = builtins.map (
      path: replaceVars path (builtins.dirOf (lib.path.removePrefix ./config path))
    ) (lib.filesystem.listFilesRecursive ./config);
  };
in
{
  config = {
    home.packages = with pkgs; [
      vim
    ];
    xdg = {
      configFile = {
        "vim" = {
          source = config;
          recursive = true;
        };
      };
    };
  };
}

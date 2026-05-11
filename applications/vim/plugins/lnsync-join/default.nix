{
  pkgs,
  lib,
  ...
}:
let
  lnsync = pkgs.callPackage ./lnsync.nix { };
  lnsyncJoin =
    args_@{
      name,
      paths,
      postBuild ? "",
      ...
    }:
    let
      mapPaths =
        f: paths:
        map (
          path:
          if path == null then
            null
          else if lib.isList path then
            mapPaths f path
          else
            f path
        ) paths;
      args = {
        paths = mapPaths (path: "${path}") paths;
        passAsFile = [ "paths" ];
      };
    in
    pkgs.runCommand name args ''
      mkdir -p $out
      for i in $(cat $pathsPath); do
        ${lnsync}/bin/lnsync $i $out
      done
      ${postBuild}
    '';
in
lnsyncJoin

{
  callPackage,
  lib,
  symlinkJoin,
  ...
}:
let
  sources = callPackage ./_sources/generated.nix { };
in
symlinkJoin {
  name = "vim-plugins";
  paths = lib.filter (x: x != null) (
    builtins.map (s: if s ? src then s.src else null) (lib.attrsets.attrValues sources)
  );
}

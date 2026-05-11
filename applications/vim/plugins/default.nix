{
  callPackage,
  lib,
  ...
}:
let
  sources = callPackage ./_sources/generated.nix { };
  lnsyncJoin = callPackage ./lnsync-join { };
in
lnsyncJoin {
  name = "vim-plugins";
  paths = lib.filter (x: x != null) (
    builtins.map (s: if s ? src then s.src else null) (lib.attrsets.attrValues sources)
  );
  postBuild = ''
    rm -f $out/deno.json $out/deno.jsonc
  '';
}

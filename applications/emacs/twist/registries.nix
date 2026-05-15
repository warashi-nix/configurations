{ callPackage }:
let
  sources = callPackage ./_sources/generated.nix { };
in
[
  {
    name = "melpa";
    type = "melpa";
    path = sources.melpa.src + "/recipes";
  }
  {
    name = "gnu-elpa";
    type = "elpa";
    path = sources.gnu-elpa.src + "/elpa-packages";
  }
  {
    name = "nongnu-elpa";
    type = "elpa";
    path = sources.nongnu-elpa.src + "/elpa-packages";
  }
  {
    name = "emacsmirror";
    type = "gitmodules";
    path = sources.epkgs.src + "/.gitmodules";
  }
]

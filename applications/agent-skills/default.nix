{ pkgs, ... }:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
in
{
  programs.agent-skills = {
    enable = true;
    sources = {
      # keep-sorted start block=yes
      mattpocock = {
        path = sources.mattpocock-skills.src;
        subdir = "skills";
        idPrefix = "mattpocock";
      };
      # keep-sorted end
    };
    skills = {
      enable = [
        # keep-sorted start
        "mattpocock/productivity/grilling"
        # keep-sorted end
      ];
    };
    targets = {
      # keep-sorted start block=yes
      copilot = {
        enable = true;
        structure = "copy-tree";
      };
      # keep-sorted end
    };
  };
}

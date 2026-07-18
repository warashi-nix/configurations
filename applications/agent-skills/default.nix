{ pkgs, ... }:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
in
{
  programs.agent-skills = {
    enable = true;
    sources = {
      # keep-sorted start block=yes
      mattpocock-productivity = {
        path = sources.mattpocock-skills.src;
        subdir = "skills/productivity";
      };
      warashi = {
        path = ./skills;
      };
      # keep-sorted end
    };
    skills = {
      enable = [
        # keep-sorted start
        "grilling"
        # keep-sorted end
      ];
      enableAll = [
        "warashi"
      ];
    };
    targets = {
      # keep-sorted start block=yes
      claude = {
        enable = true;
        structure = "copy-tree";
      };
      copilot = {
        enable = true;
        structure = "copy-tree";
      };
      # keep-sorted end
    };
  };
}

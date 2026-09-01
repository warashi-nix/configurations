{ pkgs, ... }:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
in
{
  # agent-skills のバンドルはターゲット間で共通なため、Claude Code に配る skill だけを
  # 選ぶ経路として warashi.claude.skills を使う
  warashi.claude.skills = {
    # keep-sorted start
    pair-programming = ./skills/pair-programming;
    # keep-sorted end
  };

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
        enable = false;
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

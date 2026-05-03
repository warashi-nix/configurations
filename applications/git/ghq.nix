{ pkgs, ... }:
{
  home.packages = [
    pkgs.ghq
  ];
  programs.git.settings.ghq = {
    user = "Warashi";
    root = [
      "~/ghq/"
    ];
  };
}

{ conifg, pkgs, ... }:
{
  programs.go = {
    enable = true;
    package = pkgs.go_latest;
  };

  home = {
    sessionPath = [
      "${config.home.homeDirectory}/go/bin"
    ];
  };
}

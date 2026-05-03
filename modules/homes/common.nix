{
  inputs,
  pkgs,
  config,
  ...
}:
{
  programs = {
    home-manager.enable = true;
  };

  home = {
    preferXdgDirectories = true;

    sessionPath = [
      "$HOME/.local/bin"
    ];

    sessionVariables = {
      EDITOR = "vim";
    };

    stateVersion = "24.11";
  };

  xdg.enable = true;

  imports = [
    ../../applications
  ];
}

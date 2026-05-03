{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
    installBatSyntax = false;
    enableFishIntegration = true;
    clearDefaultKeybinds = false;
    settings = {
      theme = "catppuccin-frappe";
      font-size = 11;
      font-family = "Moralerspace Radon";
      shell-integration = "none";
      working-directory = "home";
      window-inherit-working-directory = false;
      macos-option-as-alt = true;
      macos-titlebar-style = "hidden";
      keybind = [
        "shift+enter=text:\\n"
      ];
    };
  };
}

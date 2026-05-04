{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
    clearDefaultKeybinds = false;
    settings = {
      font-size = 18;
      font-family = "UDEV Gothic NFLG";
      theme = "light:Modus Operandi,dark:Modus Vivendi";
      shell-integration = "none";
      working-directory = "home";
      window-inherit-working-directory = false;
      tab-inherit-working-directory = false;
      split-inherit-working-directory = true;
      macos-option-as-alt = true;
      keybind = [
        "shift+enter=text:\\n"
      ];
    };
  };
}

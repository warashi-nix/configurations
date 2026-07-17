{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
    clearDefaultKeybinds = false;
    settings = {
      font-size = 18;
      font-family = "PlemolJP Console NF";
      theme = "light:Modus Operandi,dark:Modus Vivendi";
      shell-integration = "none";
      working-directory = "home";
      window-inherit-working-directory = false;
      tab-inherit-working-directory = false;
      split-inherit-working-directory = true;
      notify-on-command-finish-action = "bell,notify";
      bell-features = "system,attention,title,border";
      macos-option-as-alt = true;
      macos-titlebar-style = "tabs";
      keybind = [
        "shift+enter=text:\\n"
      ];
    };
  };
}

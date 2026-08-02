{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
    # デフォルトキーバインドは ctrl+tab など端末アプリが使いたいキーまで
    # 奪ってしまい、Ghostty の更新で増えるたびに同じ問題が再発する。使うもの
    # だけを明示し、残りは全て端末アプリへ素通しさせる。
    clearDefaultKeybinds = true;
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

        "cmd+c=copy_to_clipboard"
        "cmd+v=paste_from_clipboard"
        "ctrl+shift+c=copy_to_clipboard"
        "ctrl+shift+v=paste_from_clipboard"

        "cmd+n=new_window"
        "cmd+t=new_tab"
        "cmd+w=close_surface"
        "cmd+shift+[=previous_tab"
        "cmd+shift+]=next_tab"
        "cmd+1=goto_tab:1"
        "cmd+2=goto_tab:2"
        "cmd+3=goto_tab:3"
        "cmd+4=goto_tab:4"
        "cmd+5=goto_tab:5"
        "cmd+6=goto_tab:6"
        "cmd+7=goto_tab:7"
        "cmd+8=goto_tab:8"
        "cmd+9=last_tab"

        "cmd+d=new_split:right"
        "cmd+shift+d=new_split:down"
        "cmd+[=goto_split:previous"
        "cmd+]=goto_split:next"

        "cmd+q=quit"
        "cmd+,=open_config"
        "cmd+shift+,=reload_config"
        "cmd+enter=toggle_fullscreen"
        "cmd+==increase_font_size:1"
        "cmd+-=decrease_font_size:1"
        "cmd+0=reset_font_size"
      ];
    };
  };
}

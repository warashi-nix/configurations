{
  # Wayland の GTK3 は settings.ini より gsettings を優先して読むので、dconf に書く。
  dconf.settings."org/gnome/desktop/interface".gtk-key-theme = "Emacs";
}

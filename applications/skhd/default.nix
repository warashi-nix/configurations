{ pkgs, ... }: {
  services = {
    skhd = {
      enable = pkgs.stdenv.isDarwin;
      config = ''
        meh - e : open -a Emacs.app
        meh - t : open -a Ghostty.app
        meh - i : open -a Alacritty.app --args --command ${lib.getExe vim-as-ime}
        hyper - i : open -na Alacritty.app --args --command ${lib.getExe vim-as-ime}
      '';
    };
  };
}

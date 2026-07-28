{ pkgs, ... }: {
  services = {
    skhd = {
      enable = pkgs.stdenv.isDarwin;
      config = ''
        meh - e : open -a Emacs.app
        meh - t : open -a Ghostty.app
      '';
    };
  };
}

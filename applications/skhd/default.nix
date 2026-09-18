{ inputs, pkgs, ... }:
let
  appIdentity = pkgs.callPackage inputs.nix-mac-app-identity { };
in
{
  services = {
    skhd = {
      enable = pkgs.stdenv.hostPlatform.isDarwin;
      # 素の実行ファイルは store path で TCC に識別され rebuild ごとに権限を失うので、
      # bundle identifier で識別される .app に包む。
      package = appIdentity.mkAppBundle {
        package = pkgs.skhd;
        identifier = "com.koekeishiya.skhd";
      };
      config = ''
        meh - e : open -a Emacs.app
        meh - t : open -a Ghostty.app
      '';
    };
  };
}

{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  programs.emacs-twist = {
    inherit (inputs.my-emacs.profile.${system}) earlyInitFile;

    enable = true;
    emacsclient.enable = true;
    createInitFile = true;
    createManifestFile = true;
    config = inputs.my-emacs.packages.${system}.default;
  };
}

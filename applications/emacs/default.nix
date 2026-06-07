{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  programs.emacs-twist = {
    inherit (inputs.my-emacs.profile.${system}) earlyInitFile;

    enable = true;
    emacsclient.enable = true;
    serviceIntegration.enable = true;
    createInitFile = true;
    createManifestFile = true;
    config = inputs.my-emacs.packages.${system}.default;
  };
  launchd.agents.emacs.config = {
    EnvironmentVariables = {
      COLORTERM = "truecolor";
    };
  };
  systemd.user.services.emacs = {
    Service = {
      Environment = [
        "COLORTERM=truecolor"
      ];
    };
  };
}

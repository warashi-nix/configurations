{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  skkSources = pkgs.callPackage ./_sources/generated.nix { };
  sekkenPackage = inputs.sekken.packages.${system}.sekken;
  sekkenModels = inputs.sekken.packages.${system}.sekken-models;
  sekkenIpadic = pkgs.fetchzip {
    url = "https://github.com/daac-tools/vibrato/releases/download/v0.5.0/ipadic-mecab-2_7_0.tar.xz";
    hash = "sha256-4QwHxSjoCTIjFIPAxOV/r4TPos3aY7DGyxiALuaOKPI=";
  };
  sekkenServer = lib.getExe' sekkenPackage "sekken";
in
{
  xdg = {
    configFile = {
      emacs-sekken-bin = {
        target = "emacs/sekken/sekken";
        source = sekkenServer;
      };
      emacs-sekken-dic = {
        target = "emacs/sekken/system.dic.zst";
        source = "${sekkenIpadic}/system.dic.zst";
      };
      emacs-sekken-jisyo = {
        target = "emacs/sekken/SKK-JISYO.L";
        source = "${skkSources.skkdict.src}/SKK-JISYO.L";
      };
      emacs-sekken-model = {
        target = "emacs/sekken/model.zst";
        source = "${sekkenModels}/model.zst";
      };
      emacs-sekken-lm = {
        target = "emacs/sekken/lm.zst";
        source = "${sekkenModels}/lm.zst";
      };
    };
  };

  programs.emacs-twist = {
    inherit (inputs.my-emacs.profile.${system}) earlyInitFile;

    enable = true;
    emacsclient.enable = true;
    serviceIntegration.enable = pkgs.stdenv.hostPlatform.isLinux;
    createInitFile = true;
    createManifestFile = true;
    config = inputs.my-emacs.packages.${system}.default;
    # Emacs.app は appIdentity 側で署名してから入れるので、twist からは入れない。
    appBundle.enable = false;
  };

  targets.darwin.appIdentity.apps = lib.optional pkgs.stdenv.hostPlatform.isDarwin config.programs.emacs-twist.appBundle.package;
  systemd.user.services.emacs = {
    Service = {
      Environment = [
        "COLORTERM=truecolor"
        "SSH_AUTH_SOCK=${config.home.homeDirectory}/.ssh/ssh_auth_sock"
      ];
    };
  };
}

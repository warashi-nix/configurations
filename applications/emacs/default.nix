{
  inputs,
  config,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  skkSources = pkgs.callPackage ../yaskkserv2/_sources/generated.nix { };
  # nskk の見出し前方一致は prolog の trie しか引かないため、辞書をローカル
  # に読ませる必要がある。nskk-dict-load-system-dictionaries は
  # coding-system を渡さず undecided で decode するので、EUC-JP のまま渡す
  # と化ける。UTF-8 に変換し、coding cookie も合わせて書き換えて置く。
  skk-jisyo-l = pkgs.runCommand "SKK-JISYO.L-utf8" { } ''
    ${pkgs.nkf}/bin/nkf -E -w '${skkSources.skkdict.src}/SKK-JISYO.L' \
      | sed '1s/coding: euc-jp/coding: utf-8/' > $out
  '';
in
{
  xdg = {
    configFile = {
      emacs-ddskk-init-el = {
        target = "emacs/ddskk/init.el";
        source = ./ddskk/init.el;
      };
      emacs-nskk-jisyo-l = {
        target = "emacs/nskk/SKK-JISYO.L";
        source = skk-jisyo-l;
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
  };
  systemd.user.services.emacs = {
    Service = {
      Environment = [
        "COLORTERM=truecolor"
        "SSH_AUTH_SOCK=${config.home.homeDirectory}/.ssh/ssh_auth_sock"
      ];
    };
  };
}

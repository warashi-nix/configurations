{
  inputs,
  config,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  skkSources = pkgs.callPackage ../yaskkserv2/_sources/generated.nix { };
  sekkenPackage = inputs.sekken.packages.${system}.sekken;
  sekkenRelease = "v${sekkenPackage.version}";
  sekkenIpadic = pkgs.fetchzip {
    url = "https://github.com/daac-tools/vibrato/releases/download/v0.5.0/ipadic-mecab-2_7_0.tar.xz";
    hash = "sha256-4QwHxSjoCTIjFIPAxOV/r4TPos3aY7DGyxiALuaOKPI=";
  };
  sekkenModel = pkgs.fetchurl {
    url = "https://github.com/Warashi/sekken/releases/download/${sekkenRelease}/model.zst";
    hash = "sha256-QmEs9+F3gVyOThpeTI7HvRuLdhbV5qxgW64z4PSzO2g=";
  };
  sekkenLm = pkgs.fetchurl {
    url = "https://github.com/Warashi/sekken/releases/download/${sekkenRelease}/lm.zst";
    hash = "sha256-oT6tS3Q7Xc0YIzPGIFZpe1Qy94Q4el1JtYxnb4OCfNY=";
  };
  # LM の読み込みログを Emacs の非同期 stderr pipe に書くと Rust の stdio が
  # status 101 で落ちる。診断を捨てず、通常ファイルへ書く wrapper を挟む。
  sekkenServer = pkgs.writeShellScript "sekken" ''
    stateDir="''${XDG_STATE_HOME:-"$HOME/.local/state"}/sekken"
    ${pkgs.coreutils}/bin/mkdir -p "$stateDir"
    exec ${sekkenPackage}/bin/sekken "$@" 2>>"$stateDir/server.log"
  '';
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
        source = skk-jisyo-l;
      };
      emacs-sekken-model = {
        target = "emacs/sekken/model.zst";
        source = sekkenModel;
      };
      emacs-sekken-lm = {
        target = "emacs/sekken/lm.zst";
        source = sekkenLm;
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

{
  inputs = {
    nixpkgs.follows = "";
    twist.follows = "";
    org-babel.follows = "";
    emacs-spectreshell.follows = "";
  };
  outputs =
    inputs:
    let
      forAllSystems = inputs.nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    rec {
      profile = forAllSystems (
        system:
        let
          pkgs = import (inputs.nixpkgs) {
            inherit system;
            config.allowUnfree = true;
          };

          initElisp = inputs.org-babel.lib.tangleOrgBabel { } (builtins.readFile ./init.org);
          earlyInitElisp = inputs.org-babel.lib.tangleOrgBabel { } (builtins.readFile ./early-init.org);

          # init 本文をローカルパッケージとして byte/native コンパイル (AOT) する。
          # src が derivation なので、ヘッダ解析や :files 展開に頼ると IFD に
          # なる。twist が src を読まずに済むよう、派生されるメタデータは
          # すべてここで与える。
          orgTangledPackage = name: elisp: packageRequires: {
            src = pkgs.writeTextDir "${name}.el" ''
              ${elisp}
              (provide '${name})
              ;;; ${name}.el ends here
            '';
            files = {
              "${name}.el" = "${name}.el";
            };
            version = "0";
            author = null;
            meta = {
              description = "Warashi's Emacs configuration tangled from org files";
            };
            inherit packageRequires;
          };
        in
        rec {
          emacsPackage = pkgs.emacs31;
          lockDir = ./lock;
          extraRecipeDir = ./recipes;
          localPackages = [
            "consult-git-wit"
            "nskk-corfu-henkan"
            "spectreshell"
            "warashi-agent-shell"
            "warashi-agent-shell-list"
            "warashi-nskk-cursor"
            "warashi-nskk-im"
            "warashi-nskk-marker"
            "warashi-nskk-map"
            "warashi-init"
            "warashi-early-init"
          ];
          inputOverrides = {
            consult-git-wit = _: _: {
              src = ./packages/consult-git-wit;
            };
            nskk-corfu-henkan = _: _: {
              src = ./packages/nskk-corfu-henkan;
            };
            warashi-agent-shell = _: _: {
              src = ./packages/warashi-agent-shell;
            };
            warashi-agent-shell-list = _: _: {
              src = ./packages/warashi-agent-shell-list;
            };
            warashi-nskk-cursor = _: _: {
              src = ./packages/warashi-nskk-cursor;
            };
            warashi-nskk-im = _: _: {
              src = ./packages/warashi-nskk-im;
            };
            warashi-nskk-marker = _: _: {
              src = ./packages/warashi-nskk-marker;
            };
            warashi-nskk-map = _: _: {
              src = ./packages/warashi-nskk-map;
            };
            spectreshell =
              _: _:
              let
                built = inputs.emacs-spectreshell.packages.${system}.default;
              in
              {
                src = inputs.emacs-spectreshell.outPath;
                # ネイティブモジュールと terminfo はビルド産物でソースツリーに
                # 存在しないため、レシピの :files では同梱できない。src を
                # ビルド済みパッケージへ差し替えると files 展開が IFD になる
                # ので、src はソースのまま preBuild で zig-out レイアウト
                # (spectreshell.el のモジュール探索パス) にコピーする。
                preBuild = ''
                  mkdir -p zig-out/lib zig-out/share
                  cp ${built}/lib/libspectreshell.* zig-out/lib/
                  cp -r ${built}/share/terminfo zig-out/share/terminfo
                '';
              };
            warashi-init =
              _: _:
              orgTangledPackage "warashi-init" initElisp (
                # コンパイル時に setup のマクロ展開と各パッケージの解決が
                # 必要なので、init が使う全パッケージを依存に含める。
                inputs.nixpkgs.lib.genAttrs ([ "setup" ] ++ (initParser initElisp).elispPackages) (_: "0")
              );
            warashi-early-init = _: _: orgTangledPackage "warashi-early-init" earlyInitElisp { };
          };
          extraPackages = [
            "setup"
            "warashi-init"
            "warashi-early-init"
          ];
          extraSiteStartElisp = ''
            (add-to-list 'treesit-extra-load-path "${
              emacsPackage.pkgs.treesit-grammars.with-grammars (
                _:
                builtins.filter (
                  grammar: pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform grammar
                ) pkgs.tree-sitter.allGrammars
              )
            }/lib/")
          '';
          initParser = inputs.twist.lib.parseSetup { inherit (inputs.nixpkgs) lib; } { }; # for setup.el
          # 実際に読み込ませる init.el / early-init.el は AOT コンパイル済み
          # パッケージへのローダのみにする。パッケージ探索はローダではなく
          # タングル済み本文を initReader で解析して従来どおり行う。
          initFiles = [
            (pkgs.writeText "init.el" ''
              ;;; init.el ---  -*- lexical-binding: t -*-
              ;;; Code:
              (require 'warashi-init)
              ;;; init.el ends here
            '')
          ];
          initReader = _: initParser initElisp;
          earlyInitFile = pkgs.writeText "early-init.el" ''
            ;;; early-init.el ---  -*- lexical-binding: t -*-
            ;;; Code:
            (require 'warashi-early-init)
            ;;; early-init.el ends here
          '';
          registries = pkgs.callPackage ./registries.nix { };
          exportManifest = true;
        }
      );
      checks = forAllSystems (
        system:
        let
          pkgs = import (inputs.nixpkgs) {
            inherit system;
            config.allowUnfree = true;
          };
          # テストは twist がビルドした env の Emacs で走らせる。
          # nskk-corfu-henkan のテストは nskk を本物として駆動するので、
          # 素の Emacs にスタブを積む方式では成立しない。env は host 構成が
          # どのみちビルドするものなので、CI 上の追加コストはほぼ無い。
          emacs = packages.${system}.default;
          hasTest = name: builtins.pathExists (./packages + "/${name}/${name}-test.el");
          testablePackages = builtins.filter hasTest (builtins.attrNames (builtins.readDir ./packages));
        in
        builtins.listToAttrs (
          map (name: {
            name = "emacs-${name}";
            value =
              pkgs.runCommand "emacs-${name}-test"
                {
                  nativeBuildInputs = [ emacs ];
                }
                ''
                  # -L で env 側の同名パッケージより手前にソースを置く。
                  cd ${./packages}/${name}
                  emacs -Q --batch -L . -l ${name}-test.el -f ert-run-tests-batch-and-exit
                  touch $out
                '';
          }) testablePackages
        )
      );
      packages = forAllSystems (
        system:
        let
          pkgs = import (inputs.nixpkgs) {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          default = inputs.twist.lib.makeEnv {
            inherit pkgs;
            inherit (profile.${system})
              emacsPackage
              localPackages
              inputOverrides
              extraPackages
              extraSiteStartElisp
              initFiles
              initParser
              initReader
              lockDir
              exportManifest
              ;

            registries = [
              {
                name = "custom";
                type = "melpa";
                path = profile.${system}.extraRecipeDir;
              }
            ]
            ++ profile.${system}.registries;
          };
        }
      );
    };
}

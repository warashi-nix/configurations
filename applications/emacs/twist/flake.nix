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

          # define tangleOrgBabelFile here to avoid using overlays.
          tangleOrgBabelFile =
            name: path: options:
            pkgs.writeText name (inputs.org-babel.lib.tangleOrgBabel options (builtins.readFile path));
        in
        rec {
          emacsPackage = pkgs.emacs31;
          lockDir = ./lock;
          extraRecipeDir = ./recipes;
          localPackages = [
            "consult-git-wit"
            "spectreshell"
          ];
          inputOverrides = {
            consult-git-wit = _: _: {
              src = ./packages/consult-git-wit;
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
          };
          extraPackages = [ "setup" ];
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
          initFiles = [ (tangleOrgBabelFile "init.el" ./init.org { }) ];
          earlyInitFile = tangleOrgBabelFile "early-init.el" ./early-init.org { };
          registries = pkgs.callPackage ./registries.nix { };
          exportManifest = true;
        }
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

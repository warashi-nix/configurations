{
  inputs = {
    nixpkgs.follows = "";
    twist.follows = "";
    org-babel.follows = "";
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
        {
          emacsPackage = pkgs.emacs-nox;
          lockDir = ./lock;
          extraRecipeDir = ./recipes;
          extraPackages = [ "setup" ];
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
          inherit (profile.${system}) tangleOrgBabelFile;
          default = inputs.twist.lib.makeEnv {
            inherit pkgs;
            inherit (profile.${system})
              emacsPackage
              extraPackages
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

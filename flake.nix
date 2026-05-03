{
  inputs = {
    # keep-sorted start block=yes
    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    direnv-instant = {
      url = "github:Mic92/direnv-instant";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        flake-compat.follows = "";
        gitignore.follows = "";
        nixpkgs.follows = "nixpkgs";
      };
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # keep-sorted end
  };

  outputs =
    { self, flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        # keep-sorted start
        ./flake-module.nix
        ./hosts.nix
        inputs.devshell.flakeModule
        inputs.git-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
        # keep-sorted end
      ];

      perSystem =
        {
          config,
          pkgs,
          ...
        }:
        {
          pre-commit = {
            check.enable = true;
            settings = {
              src = ./.;
              hooks = {
                actionlint.enable = false;
                treefmt.enable = true;
              };
            };
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              # keep-sorted start
              keep-sorted.enable = true;
              nixfmt.enable = true;
              pinact.enable = true;
              # keep-sorted end
            };
            settings = {
              formatter = {
                # keep-sorted start block=yes
                nixfmt = {
                  excludes = [
                    "**/_sources/generated.nix" # nvfetcher generatee sources
                  ];
                };
                tombi = {
                  command = pkgs.lib.getExe pkgs.tombi;
                  options = [ "format" ];
                  includes = [ "*.toml" ];
                };
                # keep-sorted end
              };
            };
          };

          devshells.default = {
            devshell = {
              packages =
                with pkgs;
                [
                  # keep-sorted start
                  just
                  nix-output-monitor
                  nvfetcher
                  # keep-sorted end
                ]
                ++ config.pre-commit.settings.enabledPackages;
              startup = {
                pre-commit = {
                  text = config.pre-commit.shellHook;
                };
              };
            };
          };
        };
    };
}

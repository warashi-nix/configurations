{
  inputs = {
    # keep-sorted start block=yes
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs = {
        home-manager.follows = "home-manager";
        nixpkgs.follows = "nixpkgs";
      };
    };
    chelly = {
      url = "github:Warashi/chelly";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
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
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    emacs-twist = {
      url = "github:Warashi/twist.nix/darwin-emacs-app";
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
    my-emacs = {
      url = "path:./applications/emacs/twist";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        org-babel.follows = "org-babel";
        twist.follows = "emacs-twist";
      };
    };
    my-emacs-pkgs = {
      url = "path:./applications/emacs/twist/lock";
    };
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };
    org-babel = {
      url = "github:emacs-twist/org-babel";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # keep-sorted end
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://warashi.cachix.org"
    ];

    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "warashi.cachix.org-1:rtCm332XStmyk6/izNzI4hvpj5+14lMCIFbwEAgwAyw="
    ];
  };

  outputs =
    { self, flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { flake-parts-lib, ... }:
      let
        inherit (flake-parts-lib) importApply;
        flakeModules.default = importApply ./flake-module.nix { localFlake = self; };
      in
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        imports = [
          # keep-sorted start
          ./hosts.nix
          flakeModules.default
          inputs.devshell.flakeModule
          inputs.git-hooks.flakeModule
          inputs.treefmt-nix.flakeModule
          # keep-sorted end
        ];

        flake = {
          inherit flakeModules;
        };

        perSystem =
          {
            inputs',
            config,
            pkgs,
            ...
          }:
          {
            apps = inputs'.my-emacs.packages.default.makeApps {
              lockDirName = "applications/emacs/twist/lock";
            };
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
                shfmt.enable = true;
                # keep-sorted end
              };
              settings = {
                formatter = {
                  # keep-sorted start block=yes
                  nixfmt = {
                    excludes = [
                      "**/_sources/generated.nix" # nvfetcher generated sources
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
                    age
                    devcontainer
                    just
                    nix-output-monitor
                    nvfetcher
                    sops
                    ssh-to-age
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
      }
    );
}

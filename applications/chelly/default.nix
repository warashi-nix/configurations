{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
with lib;
let
  cfg = config.warashi.chelly;
  tomlFormat = pkgs.formats.toml { };
  # 既定値をまとめて mkDefault すると定義全体が捨てられて一部だけの上書きができなくなるため、葉ごとに mkDefault する
  # リストは同一優先度の定義同士が結合されるようにするため mkDefault を付けない
  mkDefaultLeaves = mapAttrsRecursive (_path: value: if isList value then value else mkDefault value);
  runtimeOptionsList = concatLists (
    mapAttrsToList (
      runtime: subcommands:
      mapAttrsToList (subcommand: args: { inherit runtime subcommand args; }) subcommands
    ) cfg.runtime_options
  );
in
{
  options.warashi.chelly = {
    enable = mkOption {
      type = types.bool;
      description = "Enable Chelly options.";
      default = true;
    };
    package = mkOption {
      type = types.package;
      description = "Package for Chelly.";
      default = inputs.chelly.packages.${pkgs.stdenv.hostPlatform.system}.chelly;
    };
    dockerfile = mkOption {
      type = types.path;
      description = "Dockerfile for Chelly.";
      default = ./Dockerfile;
    };
    envfiles = mkOption {
      type = types.listOf types.path;
      description = "Envfile for Chelly.";
      default = [ config.sops.secrets.chelly-dotenv.path ];
    };
    uid = mkOption {
      type = types.int;
      description = "uid for container user.";
    };
    gid = mkOption {
      type = types.int;
      description = "gid for container user.";
    };
    runtime_options = mkOption {
      type = types.attrsOf (types.attrsOf (types.listOf types.str));
      default = { };
      description = ''
        Runtime options for Chelly, keyed by runtime and subcommand.
        settings.runtime_options はここから生成されるため直接定義しない。
        chelly は runtime と subcommand の重複を拒否するが、この形なら構造上重複せず、
        引数リストは同一優先度の定義同士が結合されるため追記できる。
      '';
    };
    settings = mkOption {
      type = tomlFormat.type;
      default = { };
      description = ''
        Settings for Chelly.
        既定値は葉ごとに mkDefault されているため、必要な項目だけを上書きできる。
        リストは mkDefault されておらず、追加の定義は既定値と結合される。
      '';
    };
  };

  config = mkIf cfg.enable {
    sops.secrets.chelly-dotenv = { };
    home.packages = [ cfg.package ];

    warashi.chelly = {
      runtime_options = {
        podman = {
          build = [
            "--build-arg=UID=${toString cfg.uid}"
            "--build-arg=GID=${toString cfg.gid}"
          ];
          run = [
            # keep-sorted start
            "--cap-add=SYS_ADMIN,SETUID,SETGID"
            "--detach-keys=ctrl-^,ctrl-^"
            "--device=/dev/fuse"
            "--device=/dev/net/tun"
            "--security-opt=label=disable"
            "--security-opt=seccomp=unconfined"
            "--security-opt=unmask=/proc/*"
            "--userns=keep-id"
            # keep-sorted end
          ];
        };
        container = {
          build = [
            "--dns=1.1.1.1"
          ];
          run = [
            "--dns=1.1.1.1"
          ];
        };
      };

      settings =
        mkDefaultLeaves {
          additional_mounts = [
            # keep-sorted start
            "${config.home.homeDirectory}/.claude:/home/warashi/.claude"
            "${config.home.homeDirectory}/.copilot:/home/warashi/.copilot"
            "${config.home.homeDirectory}/ghq/github.com/Warashi/brainium:${config.home.homeDirectory}/ghq/github.com/Warashi/brainium"
            "${config.xdg.configHome}/git/ignore:/home/warashi/.config/git/ignore"
            "chelly-nix:/nix"
            "go-cache:/home/warashi/.cache/go-build"
            "go-mod:/home/warashi/go/pkg/mod"
            "nix-cache:/home/warashi/.cache/nix"
            # keep-sorted end
          ];
          inherit_env = [
            "COLORTERM"
            "TERM"
            "TERM_PROGRAM"
            "TERM_PROGRAM_VERSION"
          ];
          env_files = cfg.envfiles;
        }
        // {
          runtime_options = runtimeOptionsList;
        };
    };

    xdg.configFile = {
      "chelly/config.toml".source = tomlFormat.generate "chelly-config.toml" cfg.settings;
      "chelly/Dockerfile".source = cfg.dockerfile;
    };
  };
}

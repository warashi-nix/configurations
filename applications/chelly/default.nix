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
  gitIgnorePath = "${config.xdg.dataHome}/chelly/git-ignore";
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
  imports = [
    ./dedicated.nix
    ./go-proxy
  ];

  options.warashi.chelly = {
    enable = mkOption {
      type = types.bool;
      description = "Enable Chelly options. NixOS hosts use warashi.chelly-agent instead.";
      default = pkgs.stdenv.hostPlatform.isDarwin;
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
    # 専用構成では dedicated.nix の wrapper が bin/chelly を持つ。
    home.packages = optional (!cfg.dedicated) cfg.package ++ [ pkgs.podman ];

    # VM に共有するホームから Mac の /nix/store へのリンクは解決できないため、実体を渡す。
    home.activation.chelly-git-ignore = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.coreutils}/bin/install -D -m 0444 \
        ${escapeShellArg (toString config.xdg.configFile."git/ignore".source)} \
        ${escapeShellArg gitIgnorePath}
    '';

    warashi.chelly = {
      runtime_options = {
        podman = {
          build = [
            "--build-arg=UID=${toString cfg.uid}"
            "--build-arg=GID=${toString cfg.gid}"
            # remote build の context はリンクのまま送られるため、Mac 側の実体を別途渡す。
            "--file=${cfg.dockerfile}"
          ];
          run = import ./podman-run-args.nix ++ [ "--userns=keep-id" ];
        };
      };

      settings =
        mkDefaultLeaves {
          additional_mounts = [
            # keep-sorted start
            "${gitIgnorePath}:/home/warashi/.config/git/ignore"
            "chelly-nix:/nix"
            "go-cache:/home/warashi/.cache/go-build"
            "go-mod:/home/warashi/go/pkg/mod"
            "nix-cache:/home/warashi/.cache/nix"
            # keep-sorted end
          ]
          # 本人の状態は通常入口だけが使う。専用構成 (dedicated.nix) は volume と handoff clone に置き換える。
          ++ optionals (!cfg.dedicated) [
            # keep-sorted start
            "${config.home.homeDirectory}/.claude:/home/warashi/.claude"
            "${config.home.homeDirectory}/.copilot:/home/warashi/.copilot"
            "${config.home.homeDirectory}/ghq/github.com/Warashi/brainium:${config.home.homeDirectory}/ghq/github.com/Warashi/brainium"
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

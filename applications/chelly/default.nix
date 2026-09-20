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
  gitIgnorePath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.xdg.dataHome}/chelly/git-ignore"
    else
      "${config.xdg.configHome}/git/ignore";
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
  imports = [ ./host-store.nix ];

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
      # apple/container は Dockerfile を gRPC ヘッダで builder に渡すため 16 KiB までしか
      # 受け付けない (apple/container#735)。説明のコメントだけでその半分以上を占めるので、
      # コメントは repo 側の Dockerfile に残し、渡す方からは shebang と hadolint 指示以外の
      # コメント行を落とす。行継続の途中のコメントは Dockerfile でも sh でも無いので、
      # 行単位で落として構わない。
      default = pkgs.runCommand "chelly-Dockerfile" { } ''
        ${lib.getExe pkgs.gnused} -E \
          -e '/^[[:space:]]*#(!|[[:space:]]*hadolint)/b' \
          -e '/^[[:space:]]*#/d' \
          ${./Dockerfile} > "$out"
      '';
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
    nix-store = mkOption {
      type = types.enum [
        "volume"
        "host"
      ];
      default = "volume";
      description = ''
        コンテナの /nix をどこから持ってくるか。
        volume: named volume に single-user の nix を入れる。ホストに nix が無くても動く。
        host: ホストの /nix を read-only で見せ、ビルドはホストの daemon に任せる。
              host-store.nix が実装し、NixOS 側で warashi.chelly-nix-proxy が要る。
      '';
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
    home.packages = [ cfg.package ] ++ optional pkgs.stdenv.hostPlatform.isDarwin pkgs.podman;

    # VM に共有するホームから Mac の /nix/store へのリンクは解決できないため、実体を渡す。
    home.activation.chelly-git-ignore = mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.coreutils}/bin/install -D -m 0444 \
          ${escapeShellArg (toString config.xdg.configFile."git/ignore".source)} \
          ${escapeShellArg gitIgnorePath}
      ''
    );

    warashi.chelly = {
      runtime_options = {
        podman = {
          build = [
            "--build-arg=UID=${toString cfg.uid}"
            "--build-arg=GID=${toString cfg.gid}"
          ]
          # remote build の context はリンクのまま送られるため、Mac 側の実体を別途渡す。
          ++ optional pkgs.stdenv.hostPlatform.isDarwin "--file=${cfg.dockerfile}";
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
            "--build-arg=UID=${toString cfg.uid}"
            "--build-arg=GID=${toString cfg.gid}"
            "--dns=1.1.1.1"
          ];
          run = [
            "--cpus=4"
            "--memory=8G"
            "--dns=1.1.1.1"
            # VM 内でも入れ子の rootless podman には要る。newuidmap は setuid で euid 0 になるが、
            # uid_map を書くにはカーネルが対象 namespace への CAP_SYS_ADMIN を求め
            # (kernel/user_namespace.c map_write)、bounding set に無いと EPERM になる。
            "--cap-add=SYS_ADMIN"
            # 入れ子の podman が /proc を mount し直すとき、外側の /proc に masked path の
            # 上乗せ mount があると locked mount として拒まれる。podman 側の unmask=/proc/* と同じ理由。
            "--masked-path=NONE"
            # crun は入れ子コンテナの sysctl を外側の /proc/sys 経由で書くため、
            # 既定の read-only だと ping_group_range の設定で落ちる。
            # podman の unmask は read-only path も外すので、これも同じ理由。
            "--read-only-path=NONE"
          ];
        };
      };

      settings =
        mkDefaultLeaves {
          additional_mounts = [
            # keep-sorted start
            "${config.home.homeDirectory}/.claude:/home/warashi/.claude"
            "${config.home.homeDirectory}/.copilot:/home/warashi/.copilot"
            "${config.home.homeDirectory}/.pi:/home/warashi/.pi"
            "${config.home.homeDirectory}/ghq/github.com/Warashi/brainium:${config.home.homeDirectory}/ghq/github.com/Warashi/brainium"
            "${gitIgnorePath}:/home/warashi/.config/git/ignore"
            "go-cache:/home/warashi/.cache/go-build"
            "go-mod:/home/warashi/go/pkg/mod"
            "nix-cache:/home/warashi/.cache/nix"
            # keep-sorted end
          ]
          ++ optional (cfg.nix-store == "volume") "chelly-nix:/nix";
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

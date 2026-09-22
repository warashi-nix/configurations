# warashi.chelly.dedicated の実装。macOS で chelly 自体を、本人の環境・権限から
# 分離した専用構成にする。
#
# NixOS (workbench) は別の OS ユーザーを境界にし、modules/nixos/chelly-agent.nix が
# 専用入口 chelly-agent を足す。macOS には別ユーザーも sudo の入口も無いので、
# Podman machine に共有するディレクトリを境界にする。VM に見せるのは専用領域と
# ~/.local/share/chelly の実体だけで、home 全体・本人の ~/.claude・~/.copilot・
# 本人の clone は共有しない。コンテナを抜けて VM に入られても、届くのはその範囲に限る。
#
# 通常入口を別に残さないのは、本人の clone を直接 mount する経路を残すと home 側の
# repository を VM に共有することになり、この境界を自分で破るため。
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.warashi.chelly;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  dataDir = "${config.xdg.dataHome}/chelly";
  # Mac の /nix は VM に無いので、配布 bundle は git-ignore と同じく実体を置いて渡す。
  agentConfigPath = "${dataDir}/agent-config";
  agentConfig = pkgs.linkFarm "chelly-agent-config" [
    {
      name = "claude";
      path = config.warashi.claude.bundle;
    }
    {
      name = "copilot";
      path = config.warashi.copilot.bundle;
    }
  ];
  brainiumWorkspace = "${cfg.workspaces}/brainium";
  # chelly-handoff と Emacs の専用入口は chelly-agent を呼ぶ。macOS では chelly 自体が
  # 専用構成なので、そのまま chelly に渡すだけでよい。
  # brainium の mount 元だけは NixOS の runner と同じく起動のたびに用意する。podman は
  # bind mount の元を作らず、chelly-handoff remove brainium が親ごと rmdir するため。
  chellyAgent = pkgs.writeShellScriptBin "chelly-agent" ''
    ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg brainiumWorkspace}
    exec ${getExe cfg.package} "$@"
  '';
in
{
  options.warashi.chelly = {
    dedicated = mkEnableOption "running chelly itself as the dedicated agent environment (macOS)";
    workspaces = mkOption {
      type = types.str;
      default =
        if isDarwin then "${config.home.homeDirectory}/chelly-workspaces" else "/srv/chelly-workspaces";
      description = ''
        chelly-handoff が専用 clone を置く領域。
        NixOS では chelly-agent runner の作業領域、macOS では Podman machine に共有する
        ディレクトリと一致させる。
      '';
    };
  };

  config = mkIf (cfg.enable && cfg.dedicated) {
    assertions = [
      {
        assertion = isDarwin;
        message = "warashi.chelly.dedicated は macOS 用。NixOS では warashi.chelly-agent を使う";
      }
    ];

    sops.secrets.chelly-agent-dotenv = { };

    warashi.chelly = {
      # 本人の chelly-dotenv や認証状態にはフォールバックしない。
      envfiles = [ config.sops.secrets.chelly-agent-dotenv.path ];
      settings.additional_mounts = [
        # keep-sorted start
        # bundle は CHELLY_AGENT_CONFIG と同じ path で見せる。NixOS 版は /nix の mount 越しに
        # store path が届くが、Mac では実体を bind mount しないと entrypoint が黙って何も写さない。
        "${agentConfigPath}:${agentConfigPath}:ro"
        "${brainiumWorkspace}:/home/warashi/ghq/github.com/Warashi"
        "claude-state:/home/warashi/.claude"
        "copilot-state:/home/warashi/.copilot"
        # keep-sorted end
      ];
      runtime_options.podman.run = [
        "--env=CHELLY_AGENT_CONFIG=${agentConfigPath}"
        "--env=CLAUDE_CONFIG_DIR=/home/warashi/.claude"
        "--env=IS_DEMO=1"
      ];
    };

    home.packages = [ chellyAgent ];

    home.activation = {
      # linkFarm は store への symlink なので、VM から解決できるよう実体に展開する。
      # store の read-only mode を引き継ぐと次回の上書きで失敗するので mode は付け直す。
      chelly-agent-config = hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.coreutils}/bin/rm -rf ${escapeShellArg agentConfigPath}
        run ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg dataDir}
        run ${pkgs.coreutils}/bin/cp -RL --no-preserve=mode ${agentConfig} ${escapeShellArg agentConfigPath}
      '';
      # podman は bind mount の元を作らない。brainium の handoff clone が無くても
      # 起動できるよう、専用領域とその親を先に用意する。
      chelly-workspaces = hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg brainiumWorkspace}
      '';
    };
  };
}

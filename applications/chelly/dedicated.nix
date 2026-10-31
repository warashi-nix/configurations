# macOS の chelly を、本人の環境・権限から分離した専用構成にする。
#
# NixOS (workbench) は別の OS ユーザーを境界にし、modules/nixos/chelly-agent.nix が
# 専用入口 chelly を足す。macOS には別ユーザーも sudo の入口も無いので、
# Podman machine に共有するディレクトリを境界にする。VM に見せるのは専用領域と
# ~/.local/share/chelly の実体だけで、home 全体・本人の ~/.claude・~/.copilot・
# 本人の clone は共有しない。コンテナを抜けて VM に入られても、届くのはその範囲に限る。
#
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
  # brainium の mount 元は NixOS の runner と同じく起動のたびに用意する。podman は
  # bind mount の元を作らず、chelly-handoff remove brainium が親ごと rmdir するため。
  script = pkgs.writeShellScriptBin "chelly" ''
    ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg brainiumWorkspace}
    exec ${getExe cfg.package} "$@"
  '';
  completions = pkgs.callPackage ./completions.nix { chelly = cfg.package; };
  wrapper = pkgs.symlinkJoin {
    name = "chelly-wrapper";
    paths = [
      script
      completions
    ];
    passthru = { inherit script completions; };
  };
in
{
  options.warashi.chelly = {
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

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = isDarwin;
        message = "warashi.chelly は macOS 用。NixOS では warashi.chelly-agent を使う";
      }
    ];

    sops.secrets.chelly-agent-dotenv = { };

    warashi.chelly = {
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

    home.packages = [ wrapper ];

    # machine は home-manager の activation が、無いときだけ宣言どおりに init する。
    # 既存 machine の volumes は変えられないので、共有範囲を変えるときは本人が
    # podman machine rm を実行してから switch する。
    services.podman = {
      enable = true;
      package = pkgs.podman;
      # 既定 machine は /Users を丸ごと共有するので、境界に反する。
      useDefaultMachine = false;
      # provider を containers.conf に書き、CONTAINERS_MACHINE_PROVIDER の export を不要にする。
      settings.containers.machine.provider = "applehv";
      machines.chelly = {
        cpus = 4;
        memory = 8192;
        rootful = false;
        volumes = [
          "${cfg.workspaces}:${cfg.workspaces}"
          "${dataDir}:${dataDir}"
        ];
        # watchdog は stop しても起動し直すので、起動・停止は本人の操作に残す。
        autoStart = false;
      };
    };

    home.activation = {
      # linkFarm は store への symlink なので、VM から解決できるよう実体に展開する。
      # store の read-only mode を引き継ぐと次回の上書きで失敗するので mode は付け直す。
      # machine の init より前に mount 元を用意する。VM 起動時に無い source は共有できない。
      chelly-agent-config = hm.dag.entryBetween [ "podmanMachines" ] [ "writeBoundary" ] ''
        run ${pkgs.coreutils}/bin/rm -rf ${escapeShellArg agentConfigPath}
        run ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg dataDir}
        run ${pkgs.coreutils}/bin/cp -RL --no-preserve=mode ${agentConfig} ${escapeShellArg agentConfigPath}
      '';
      # podman は bind mount の元を作らない。brainium の handoff clone が無くても
      # 起動できるよう、専用領域とその親を先に用意する。
      chelly-workspaces = hm.dag.entryBetween [ "podmanMachines" ] [ "writeBoundary" ] ''
        run ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg brainiumWorkspace}
      '';
    };
  };
}

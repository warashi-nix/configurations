{
  lib,
  runCommand,
  bash,
  coreutils,
  gawk,
  jq,
  nix,
  athena,
  workbench,
  athenaPkgs,
  workbenchPkgs,
  homeManagerLib,
  chellyModuleInputs,
  stdenv,
}:
let
  macHome = athena.home-manager.users.warashi;
  linuxHome = workbench.home-manager.users.warashi;

  # macHome.home.packages / linuxHome.home.packages は完全な host config が
  # ../../applications 配下に持ち込む無関係なパッケージ (twist 経由の emacs など) まで
  # 含んでおり、それらの .pname を評価しようとすると Darwin 向け IFD ビルドが要求されて
  # aarch64-linux では失敗する。Podman の有無だけを見るテストは、chelly の
  # home-manager モジュールと対応する host の homes/chelly.nix だけを取り込んだ
  # 最小構成を評価することで、無関係なパッケージを辿らずに済ませる。
  #
  # sops-nix 本体の home-manager モジュールは鍵ソースの assertion を要求するため、
  # ここでは cfg.envfiles が参照する sops.secrets.*.path だけを提供する最小限の
  # スタブに留める。
  sopsSecretsStub =
    { lib, ... }:
    {
      options.sops.secrets = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options.path = lib.mkOption {
                type = lib.types.str;
                default = "/run/secrets/${name}";
              };
            }
          )
        );
        default = { };
      };
    };

  # dedicated.nix は本人の Claude/Copilot の配布 bundle を参照する。最小構成では
  # applications/claude と copilot を取り込まず、bundle の option だけを空の store path で満たす。
  agentBundleStub =
    { lib, pkgs, ... }:
    {
      options.warashi.claude.bundle = lib.mkOption {
        type = lib.types.package;
        default = pkgs.emptyDirectory;
      };
      options.warashi.copilot.bundle = lib.mkOption {
        type = lib.types.package;
        default = pkgs.emptyDirectory;
      };
    };

  chellyHomeConfig =
    { pkgs, hostHomeModule }:
    (homeManagerLib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inputs = chellyModuleInputs;
        # nix-store = "host" (workbench) は host-store.nix が osConfig.warashi.chelly-nix-proxy
        # を要求する。実ホストでは hosts/workbench/chelly.nix が有効にしているものを、
        # NixOS 側を丸ごと評価せずに満たすための最小限のスタブ。
        osConfig = {
          warashi.chelly-nix-proxy = {
            enable = true;
            socket-dir = "/run/chelly-nix";
          };
          nix.package = pkgs.nix;
        };
      };
      modules = [
        sopsSecretsStub
        agentBundleStub
        ./default.nix
        hostHomeModule
        {
          home = {
            username = "warashi";
            homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/warashi" else "/home/warashi";
            stateVersion = "24.11";
          };
        }
      ];
    }).config;

  installsPackage =
    pname: home: lib.any (package: (package.pname or package.name or "") == pname) home.home.packages;
  installsPodman = installsPackage "podman";
  macRunArgs = macHome.warashi.chelly.runtime_options.podman.run;
  macMounts = macHome.warashi.chelly.settings.additional_mounts;
  macWorkspaces = "${macHome.home.homeDirectory}/chelly-workspaces";

  darwinChellyHome = chellyHomeConfig {
    pkgs = athenaPkgs;
    hostHomeModule = ../../hosts/athena/homes/chelly.nix;
  };
  linuxChellyHome = chellyHomeConfig {
    pkgs = workbenchPkgs;
    hostHomeModule = ../../hosts/workbench/homes/chelly.nix;
  };

  tests = lib.runTests {
    test-mac-selects-podman = {
      expr = macHome.warashi.chelly.settings.container_cmd or null;
      expected = "podman";
    };
    test-darwin-installs-podman-with-nix = {
      expr = installsPodman darwinChellyHome;
      expected = true;
    };
    test-linux-does-not-install-podman-in-home = {
      expr = installsPodman linuxChellyHome;
      expected = false;
    };
    test-mac-does-not-install-podman-with-homebrew = {
      expr = lib.elem "podman" (map (brew: brew.name) athena.homebrew.brews);
      expected = false;
    };
    test-mac-keeps-container = {
      expr = lib.elem "container" (map (brew: brew.name) athena.homebrew.brews);
      expected = true;
    };
    test-mac-shares-all-caches = {
      expr = lib.all (mount: lib.elem mount macHome.warashi.chelly.settings.additional_mounts) [
        "chelly-nix:/nix"
        "go-cache:/home/warashi/.cache/go-build"
        "go-mod:/home/warashi/go/pkg/mod"
        "nix-cache:/home/warashi/.cache/nix"
      ];
      expected = true;
    };
    test-mac-mounts-materialized-git-ignore = {
      expr = lib.filter (
        mount: lib.hasSuffix ":/home/warashi/.config/git/ignore" mount
      ) macHome.warashi.chelly.settings.additional_mounts;
      expected = [ "${macHome.xdg.dataHome}/chelly/git-ignore:/home/warashi/.config/git/ignore" ];
    };
    test-mac-copies-git-ignore-on-activation = {
      expr = macHome.home.activation ? chelly-git-ignore;
      expected = true;
    };
    test-mac-installs-read-only-git-ignore = {
      expr = lib.hasInfix "/bin/install -D -m 0444" macHome.home.activation.chelly-git-ignore.data;
      expected = true;
    };
    test-remote-build-uses-dockerfile-source = {
      expr = lib.elem "--file=${macHome.warashi.chelly.dockerfile}" macHome.warashi.chelly.runtime_options.podman.build;
      expected = true;
    };
    test-linux-keeps-git-ignore-mount = {
      expr = lib.filter (
        mount: lib.hasSuffix ":/home/warashi/.config/git/ignore" mount
      ) linuxHome.warashi.chelly.settings.additional_mounts;
      expected = [ "${linuxHome.xdg.configHome}/git/ignore:/home/warashi/.config/git/ignore" ];
    };
    test-linux-does-not-copy-git-ignore = {
      expr = linuxHome.home.activation ? chelly-git-ignore;
      expected = false;
    };
    test-linux-keeps-host-store = {
      expr = linuxHome.warashi.chelly.nix-store;
      expected = "host";
    };
    # Linux の通常入口は本人の実 ~/.claude を mount するので、初回セットアップの
    # スキップも配布 bundle の適用もしない。
    test-linux-entry-keeps-owner-state = {
      expr = {
        skipsOnboarding = lib.elem "--env=IS_DEMO=1" linuxHome.warashi.chelly.runtime_options.podman.run;
        appliesBundle = lib.any (lib.hasPrefix "--env=CHELLY_AGENT_CONFIG=") linuxHome.warashi.chelly.runtime_options.podman.run;
        mountsOwnerClaude = lib.elem "${linuxHome.home.homeDirectory}/.claude:/home/warashi/.claude" linuxHome.warashi.chelly.settings.additional_mounts;
        dedicated = linuxHome.warashi.chelly.dedicated;
        workspaces = linuxHome.warashi.chelly.workspaces;
      };
      expected = {
        skipsOnboarding = false;
        appliesBundle = false;
        mountsOwnerClaude = true;
        dedicated = false;
        workspaces = "/srv/chelly-workspaces";
      };
    };

    # macOS は VM の共有範囲を境界にするので、chelly 自体が専用構成になる。
    # 本人の home の状態は mount せず、専用領域と ~/.local/share/chelly の実体だけを使う。
    test-mac-dedicated-does-not-mount-owner-state = {
      expr = lib.filter (
        mount:
        lib.any (prefix: lib.hasPrefix "${macHome.home.homeDirectory}/${prefix}" mount) [
          ".claude"
          ".copilot"
          ".pi"
          "ghq"
        ]
      ) macMounts;
      expected = [ ];
    };
    test-mac-dedicated-keeps-agent-state-in-volumes = {
      expr = lib.all (mount: lib.elem mount macMounts) [
        "claude-state:/home/warashi/.claude"
        "copilot-state:/home/warashi/.copilot"
        "${macWorkspaces}/brainium:/home/warashi/ghq/github.com/Warashi"
      ];
      expected = true;
    };
    test-mac-dedicated-mount-sources-stay-in-shared-paths = {
      expr = lib.filter (
        mount:
        lib.hasPrefix "/" mount
        && !(lib.any (prefix: lib.hasPrefix prefix mount) [
          "${macWorkspaces}/"
          "${macHome.xdg.dataHome}/chelly/"
        ])
      ) macMounts;
      expected = [ ];
    };
    test-mac-dedicated-applies-bundle-and-skips-onboarding = {
      expr = {
        bundle = lib.filter (lib.hasPrefix "--env=CHELLY_AGENT_CONFIG=") macRunArgs;
        configDir = lib.elem "--env=CLAUDE_CONFIG_DIR=/home/warashi/.claude" macRunArgs;
        skipsOnboarding = lib.elem "--env=IS_DEMO=1" macRunArgs;
        userns = lib.filter (lib.hasPrefix "--userns=") macRunArgs;
      };
      expected = {
        bundle = [ "--env=CHELLY_AGENT_CONFIG=${macHome.xdg.dataHome}/chelly/agent-config" ];
        configDir = true;
        skipsOnboarding = true;
        userns = [ "--userns=keep-id" ];
      };
    };
    # Mac の /nix は VM に無いので、CHELLY_AGENT_CONFIG の path はそのまま
    # bind mount で見せないと entrypoint が黙って何も写さない。
    test-mac-dedicated-mounts-bundle-at-env-path = {
      expr =
        let
          bundle = lib.removePrefix "--env=CHELLY_AGENT_CONFIG=" (
            lib.findFirst (lib.hasPrefix "--env=CHELLY_AGENT_CONFIG=") "" macRunArgs
          );
        in
        lib.filter (mount: lib.hasPrefix "${bundle}:${bundle}" mount) macMounts;
      expected = [
        "${macHome.xdg.dataHome}/chelly/agent-config:${macHome.xdg.dataHome}/chelly/agent-config:ro"
      ];
    };
    test-mac-dedicated-uses-only-agent-token = {
      expr = macHome.warashi.chelly.settings.env_files;
      expected = [ macHome.sops.secrets.chelly-agent-dotenv.path ];
    };
    test-mac-dedicated-materializes-bundle-and-workspaces = {
      expr = {
        bundle = lib.hasInfix "${macHome.xdg.dataHome}/chelly/agent-config" macHome.home.activation.chelly-agent-config.data;
        workspaces = lib.hasInfix "${macWorkspaces}/brainium" macHome.home.activation.chelly-workspaces.data;
      };
      expected = {
        bundle = true;
        workspaces = true;
      };
    };
    test-mac-dedicated-installs-chelly-agent-wrapper = {
      expr = {
        mac = installsPackage "chelly-agent" darwinChellyHome;
        linux = installsPackage "chelly-agent" linuxChellyHome;
        workspaces = darwinChellyHome.warashi.chelly.workspaces;
      };
      expected = {
        mac = true;
        linux = false;
        workspaces = "/Users/warashi/chelly-workspaces";
      };
    };
    # machine は home-manager の services.podman が宣言どおりに init する。home 全体を共有する
    # 既定 machine と、停止しても起動し直す watchdog は境界と運用に反するので無効。
    test-mac-dedicated-declares-machine-with-shared-paths-only = {
      expr = {
        enabled = macHome.services.podman.enable;
        defaultMachine = macHome.services.podman.useDefaultMachine;
        provider = macHome.services.podman.settings.containers.machine.provider or null;
        machines = lib.mapAttrs (_: machine: {
          inherit (machine)
            autoStart
            cpus
            memory
            rootful
            volumes
            ;
        }) macHome.services.podman.machines;
        linuxEnabled = linuxHome.services.podman.enable;
      };
      expected = {
        enabled = true;
        defaultMachine = false;
        provider = "applehv";
        machines.chelly = {
          autoStart = false;
          cpus = 4;
          memory = 8192;
          rootful = false;
          volumes = [
            "${macWorkspaces}:${macWorkspaces}"
            "${macHome.xdg.dataHome}/chelly:${macHome.xdg.dataHome}/chelly"
          ];
        };
        linuxEnabled = false;
      };
    };
    # chelly-handoff remove brainium は mount 元の親ごと rmdir するので、NixOS の runner と
    # 同じく wrapper が起動のたびに用意しないと次の switch まで起動できなくなる。
    test-mac-dedicated-wrapper-recreates-brainium-mount-source = {
      expr =
        let
          wrapper = lib.findFirst (
            package: (package.name or "") == "chelly-agent"
          ) null darwinChellyHome.home.packages;
        in
        wrapper != null && lib.hasInfix "mkdir -p /Users/warashi/chelly-workspaces/brainium" wrapper.text;
      expected = true;
    };
  };
in
assert lib.assertMsg (tests == [ ]) (builtins.toJSON tests);
runCommand "chelly-config-check"
  {
    nativeBuildInputs = [
      bash
      coreutils
      gawk
      jq
      nix
    ];
  }
  # 作業場所を $out ではなく $TMPDIR に置くのは、実 nix の入れ子 store や cache、
  # 実 nix の store path を埋め込んだラッパーを check の出力に残さないため。
  # 判定に使う出力は失敗時に build log へ出るので、$out には何も写さない。
  ''
    ${bash}/bin/bash ${./entrypoint-test.sh} ${./Dockerfile} "$TMPDIR/entrypoint-test" ${nix}/bin/nix ${stdenv.hostPlatform.system}
    mkdir "$out"
  ''

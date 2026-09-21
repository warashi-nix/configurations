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

  installsPodman = home: lib.any (package: (package.pname or "") == "podman") home.home.packages;

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
    test-existing-entries-do-not-skip-claude-onboarding = {
      expr = map (home: lib.elem "--env=IS_DEMO=1" home.warashi.chelly.runtime_options.podman.run) [
        macHome
        linuxHome
      ];
      expected = [
        false
        false
      ];
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

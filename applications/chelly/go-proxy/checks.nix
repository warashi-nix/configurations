{
  lib,
  runCommand,
  athenaPkgs,
  workbenchPkgs,
  homeManagerLib,
  chellyModuleInputs,
}:
let
  chellyHomeConfig = import ../test-home.nix { inherit homeManagerLib chellyModuleInputs; };
  allow = [
    "github.com/example/allowed"
    "git.example.com/team/*"
  ];
  withAllow = {
    warashi.chelly.goProxy.allow = allow;
  };

  mac = chellyHomeConfig {
    pkgs = athenaPkgs;
    hostHomeModule = ../../../hosts/athena/homes/chelly.nix;
    extraModules = [ withAllow ];
  };
  macWithoutAllow = chellyHomeConfig {
    pkgs = athenaPkgs;
    hostHomeModule = ../../../hosts/athena/homes/chelly.nix;
  };
  linux =
    extraModules:
    chellyHomeConfig {
      pkgs = workbenchPkgs;
      hostHomeModule = ../../../hosts/workbench/homes/chelly.nix;
      inherit extraModules;
    };

  agent = mac.launchd.agents.chelly-go-proxy;
  args = agent.config.ProgramArguments;
  argAfter = flag: lib.elemAt args (lib.lists.findFirstIndex (arg: arg == flag) null args + 1);
  goEnv =
    config: lib.filter (lib.hasPrefix "--env=GO") config.warashi.chelly.runtime_options.podman.run;
  # home-manager は失敗した assertion を評価時に throw するので、評価できるかで判定する。
  evaluates = config: (builtins.tryEval (builtins.seq config true)).success;

  tests = lib.runTests {
    test-runs-proxy-as-owner-launchd-agent = {
      expr = {
        inherit (agent) enable;
        inherit (agent.config) KeepAlive RunAtLoad;
        program = lib.hasSuffix "/bin/chelly-go-proxy" (lib.head args);
        home = agent.config.EnvironmentVariables.HOME;
      };
      expected = {
        enable = true;
        KeepAlive = true;
        RunAtLoad = true;
        program = true;
        home = "/Users/warashi";
      };
    };
    test-proxy-listens-only-on-loopback = {
      expr = argAfter "-listen";
      expected = "127.0.0.1:3140";
    };
    test-proxy-allows-only-configured-patterns = {
      expr = argAfter "-allow";
      expected = "github.com/example/allowed,git.example.com/team/*";
    };
    test-proxy-uses-owner-go-and-git = {
      expr = {
        go = argAfter "-go";
        git = lib.elem "${mac.programs.git.package}/bin" (
          lib.splitString ":" agent.config.EnvironmentVariables.PATH
        );
        gh = lib.elem "${mac.programs.gh.package}/bin" (
          lib.splitString ":" agent.config.EnvironmentVariables.PATH
        );
      };
      expected = {
        go = "${mac.programs.go.package}/bin/go";
        git = true;
        gh = true;
      };
    };
    # VM に共有する領域に置くと、agent が proxy の cache を書き換えて他の module を返させられる。
    test-proxy-cache-stays-outside-vm-shares = {
      expr =
        let
          cacheDir = argAfter "-cache-dir";
        in
        {
          inherit cacheDir;
          shared = lib.any (
            volume: lib.hasPrefix (lib.head (lib.splitString ":" volume)) cacheDir
          ) mac.services.podman.machines.chelly.volumes;
        };
      expected = {
        cacheDir = "/Users/warashi/.cache/chelly-go-proxy";
        shared = false;
      };
    };
    # GOPRIVATE を渡すと GONOPROXY の既定になり、private module が proxy を迂回して
    # 認証の無い direct 取得に行く。
    test-container-uses-proxy-without-goprivate = {
      expr = goEnv mac;
      expected = [
        "--env=GONOSUMDB=github.com/example/allowed,git.example.com/team/*"
        "--env=GOPROXY=http://host.containers.internal:3140,https://proxy.golang.org"
      ];
    };
    test-nothing-changes-without-allowed-modules = {
      expr = {
        agent = macWithoutAllow.launchd.agents ? chelly-go-proxy;
        env = goEnv macWithoutAllow;
      };
      expected = {
        agent = false;
        env = [ ];
      };
    };
    test-linux-is-rejected = {
      expr = {
        withAllow = evaluates (linux [ withAllow ]);
        withoutAllow = evaluates (linux [ ]);
      };
      expected = {
        withAllow = false;
        withoutAllow = true;
      };
    };
  };
in
assert lib.assertMsg (tests == [ ]) (builtins.toJSON tests);
runCommand "chelly-go-proxy-config-check" { } ''
  mkdir "$out"
''

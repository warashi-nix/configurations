{
  lib,
  runCommand,
  athenaPkgs,
  workbenchPkgs,
  homeManagerLib,
  inputs,
}:
let
  home =
    pkgs: extraModules:
    (homeManagerLib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ./default.nix
        {
          home = {
            username = "warashi";
            homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/warashi" else "/home/warashi";
            stateVersion = "24.11";
          };
        }
      ]
      ++ extraModules;
    }).config;
  withTarget = {
    warashi.locdog.targets.example = {
      watch_cmd = [
        "/bin/check"
        "arg"
      ];
      alert_cmd = [ "/bin/alert" ];
      recovery_cmd = [
        "/bin/recover"
        "done"
      ];
      interval = "1m";
      threshold = "2m";
      timeout = "30s";
      realert_interval = "1h";
    };
  };
  mac = home athenaPkgs [ withTarget ];
  linux = home workbenchPkgs [ withTarget ];
  macWithout = home athenaPkgs [ ];
  linuxWithout = home workbenchPkgs [ ];
  locdogConfig = config: builtins.fromJSON config.home.file.".config/locdog/config.json".text;
  agent = mac.launchd.agents.locdog;
  service = linux.systemd.user.services.locdog;

  tests = lib.runTests {
    test-writes-targets-where-locdog-reads-its-config = {
      expr = locdogConfig mac;
      expected = {
        targets = [
          {
            name = "example";
            watch_cmd = [
              "/bin/check"
              "arg"
            ];
            alert_cmd = [ "/bin/alert" ];
            recovery_cmd = [
              "/bin/recover"
              "done"
            ];
            interval = "1m";
            threshold = "2m";
            timeout = "30s";
            realert_interval = "1h";
          }
        ];
      };
    };
    test-runs-as-launchd-agent-on-macos = {
      expr = {
        inherit (agent) enable;
        inherit (agent.config) KeepAlive RunAtLoad;
        program = lib.hasSuffix "/bin/locdog" (lib.head agent.config.ProgramArguments);
        home = agent.config.EnvironmentVariables.HOME;
        systemd = mac.systemd.user.services ? locdog;
      };
      expected = {
        enable = true;
        KeepAlive = true;
        RunAtLoad = true;
        program = true;
        home = "/Users/warashi";
        systemd = false;
      };
    };
    test-restarts-launchd-agent-when-config-changes = {
      expr = agent.config.EnvironmentVariables.LOCDOG_CONFIG;
      expected = "${mac.home.file.".config/locdog/config.json".source}";
    };
    test-runs-as-lingering-user-service-on-linux = {
      expr = {
        program = map (lib.hasSuffix "/bin/locdog") (lib.toList service.Service.ExecStart);
        inherit (service.Service) Restart;
        wantedBy = service.Install.WantedBy;
        restartTriggers = service.Unit.X-Restart-Triggers;
        launchd = linux.launchd.agents ? locdog;
      };
      expected = {
        program = [ true ];
        Restart = "always";
        wantedBy = [ "default.target" ];
        restartTriggers = [ "${linux.home.file.".config/locdog/config.json".source}" ];
        launchd = false;
      };
    };
    test-stays-off-without-targets = {
      expr = {
        mac = macWithout.launchd.agents ? locdog;
        linux = linuxWithout.systemd.user.services ? locdog;
        config = macWithout.home.file ? ".config/locdog/config.json";
      };
      expected = {
        mac = false;
        linux = false;
        config = false;
      };
    };
  };
in
assert lib.assertMsg (tests == [ ]) (builtins.toJSON tests);
runCommand "locdog-config-check" { } ''
  mkdir "$out"
''

{
  lib,
  runCommand,
  athenaPkgs,
  workbenchPkgs,
  homeManagerLib,
  inputs,
}:
let
  # sops-nix 本体は鍵ソースの assertion を要求するので、宣言された secret と path だけを持つ
  # スタブで代える。
  sopsSecretsStub = {
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
  home =
    pkgs: extraModules:
    (homeManagerLib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        sopsSecretsStub
        ./default.nix
        ../locdog/default.nix
        ../slack-notify/default.nix
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
  enabled = {
    warashi.brainium-handoff.enable = true;
  };
  mac = home athenaPkgs [ enabled ];
  linux = home workbenchPkgs [ enabled ];
  disabled = home workbenchPkgs [ ];
  target = config: config.warashi.locdog.targets.brainium-handoff;

  tests = lib.runTests {
    test-watches-owner-brainium-and-its-handoff = {
      expr = {
        mac = lib.tail (target mac).watch_cmd;
        linux = lib.tail (target linux).watch_cmd;
        program = lib.hasSuffix "/bin/brainium-handoff-pending" (lib.head (target linux).watch_cmd);
      };
      expected = {
        mac = [
          "/Users/warashi/ghq/github.com/Warashi/brainium"
          "brainium"
        ];
        linux = [
          "/home/warashi/ghq/github.com/Warashi/brainium"
          "brainium"
        ];
        program = true;
      };
    };
    test-sends-pending-requests-to-slack = {
      expr = {
        alert = (target linux).alert_cmd;
        recovery = lib.init (target linux).recovery_cmd;
        secret = linux.sops.secrets ? slack-webhook-url;
      };
      expected = {
        alert = linux.warashi.slack-notify.command;
        recovery = linux.warashi.slack-notify.command;
        secret = true;
      };
    };
    test-command-reads-webhook-url-from-sops = {
      expr = lib.last linux.warashi.slack-notify.command;
      expected = "/run/secrets/slack-webhook-url";
    };
    test-alert-waits-for-a-failed-check-to-finish = {
      expr = {
        inherit (target linux)
          interval
          threshold
          timeout
          realert_interval
          ;
      };
      expected = {
        interval = "1m";
        threshold = "90s";
        timeout = "30s";
        realert_interval = "1h";
      };
    };
    test-stays-off-unless-enabled = {
      expr = {
        target = disabled.warashi.locdog.targets ? brainium-handoff;
        secret = disabled.sops.secrets ? slack-webhook-url;
      };
      expected = {
        target = false;
        secret = false;
      };
    };
  };
in
assert lib.assertMsg (tests == [ ]) (builtins.toJSON tests);
runCommand "brainium-handoff-config-check" { } ''
  mkdir "$out"
''

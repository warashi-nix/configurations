{
  lib,
  runCommand,
  python3,
  workbenchSystem,
}:
let
  workbench = workbenchSystem.config;
  agent = workbench.users.users.chelly-agent or { };
  owner = workbench.users.users.warashi;
  runnerRules = lib.filter (rule: rule.runAs == "chelly-agent") workbench.security.sudo.extraRules;
  runnerCommand = (lib.head (lib.head runnerRules).commands).command;
  ownerHome = workbench.home-manager.users.warashi;
  tests = lib.runTests {
    test-disabled-agent-keeps-existing-proxy-access = {
      expr =
        let
          disabled =
            (workbenchSystem.extendModules {
              modules = [ { warashi.chelly-agent.enable = lib.mkForce false; } ];
            }).config;
        in
        {
          accountExists = disabled.users.users ? chelly-agent;
          socketMode = disabled.systemd.sockets.chelly-nix-proxy.socketConfig.SocketMode;
          secretExists = disabled.sops.secrets ? chelly-agent-dotenv;
          envfiles = disabled.warashi.chelly-agent.envfiles;
        };
      expected = {
        accountExists = false;
        socketMode = "0600";
        secretExists = false;
        envfiles = [ ];
      };
    };
    test-agent-gets-only-dedicated-model-envfile = {
      expr =
        let
          secret = workbench.sops.secrets.chelly-agent-dotenv or { };
        in
        {
          owner = secret.owner or null;
          group = secret.group or null;
          mode = secret.mode or null;
          key = secret.key or null;
          path = secret.path or null;
          neededForUsers = secret.neededForUsers or null;
          envfiles = workbench.warashi.chelly-agent.envfiles;
        };
      expected = {
        owner = "chelly-agent";
        group = "chelly-agent";
        mode = "0400";
        key = "chelly-agent-dotenv";
        path = "/run/secrets/chelly-agent-dotenv";
        neededForUsers = false;
        envfiles = [ "/run/secrets/chelly-agent-dotenv" ];
      };
    };
    test-agent-cannot-join-trusted-nix-group = {
      expr =
        let
          unsafe =
            (workbenchSystem.extendModules {
              modules = [ { users.users.chelly-agent.extraGroups = [ "wheel" ]; } ];
            }).config;
        in
        lib.any (
          assertion:
          assertion.message == "chelly-agent must not be a trusted Nix user or belong to a trusted Nix group"
          && !assertion.assertion
        ) unsafe.assertions;
      expected = true;
    };
    test-only-owner-can-start-agent-runner = {
      expr = map (rule: {
        inherit (rule) users groups;
        options = map (command: command.options) rule.commands;
      }) runnerRules;
      expected = [
        {
          users = [ "warashi" ];
          groups = [ ];
          options = [
            [
              "NOPASSWD"
              "NOSETENV"
            ]
          ];
        }
      ];
    };
    test-agent-has-private-home = {
      expr = {
        home = agent.home or null;
        mode = agent.homeMode or null;
      };
      expected = {
        home = "/var/lib/chelly-agent";
        mode = "700";
      };
    };
    test-agent-has-no-owner-privileges = {
      expr = agent.extraGroups or [ ];
      expected = [ "chelly-workspaces" ];
    };
    test-agent-has-independent-subordinate-ids = {
      expr =
        lib.all (
          range:
          range.count >= 196608
          && lib.all (
            other:
            range.startUid + range.count <= other.startUid || other.startUid + other.count <= range.startUid
          ) owner.subUidRanges
        ) (agent.subUidRanges or [ ])
        && (agent.subUidRanges or [ ]) != [ ];
      expected = true;
    };
    test-agent-has-independent-subordinate-gids = {
      expr =
        lib.all (
          range:
          range.count >= 196608
          && lib.all (
            other:
            range.startGid + range.count <= other.startGid || other.startGid + other.count <= range.startGid
          ) owner.subGidRanges
        ) (agent.subGidRanges or [ ])
        && (agent.subGidRanges or [ ]) != [ ];
      expected = true;
    };
    test-agent-can-use-untrusted-proxy = {
      expr = workbench.systemd.sockets.chelly-nix-proxy.socketConfig.SocketGroup or null;
      expected = "chelly-agent";
    };
    test-proxy-keeps-untrusted-identity = {
      expr = workbench.systemd.services."chelly-nix-proxy@".serviceConfig.User;
      expected = "chelly-nix-proxy";
    };
    test-primary-user-keeps-private-home = {
      expr = owner.homeMode;
      expected = "700";
    };
    test-primary-user-can-view-workspaces = {
      expr = lib.elem "chelly-workspaces" owner.extraGroups;
      expected = true;
    };
  };
in
assert lib.assertMsg (tests == [ ]) (builtins.toJSON tests);
runCommand "chelly-agent-config-check"
  {
    nativeBuildInputs = [ python3 ];
  }
  ''
    test -f ${workbench.environment.etc.sudoers.source}

    # 専用環境へ配る設定は、本人の home-manager が host の ~/.claude に書くものと同じ生成物だけ。
    test -f ${ownerHome.warashi.claude.bundle}/CLAUDE.md
    test -f ${ownerHome.warashi.claude.bundle}/settings.json
    test -f ${ownerHome.warashi.claude.bundle}/output-styles/grilling.md
    test -f ${ownerHome.warashi.claude.bundle}/skills/pair-programming/SKILL.md
    grep -Fq '"outputStyle": "grilling"' ${ownerHome.warashi.claude.bundle}/settings.json
    test -f ${ownerHome.warashi.copilot.bundle}/copilot-instructions.md
    test -f ${ownerHome.warashi.copilot.bundle}/settings.json
    test -f ${ownerHome.warashi.copilot.bundle}/skills/pair-programming/SKILL.md
    if ${runnerCommand} run >stdout 2>stderr; then
      echo "agent runner accepted a different account" >&2
      exit 1
    fi
    test ! -s stdout
    grep -Fxq "chelly-agent: run through the chelly-agent launcher" stderr
    # podman は bind mount の元を作らないので、brainium の mount 元は runner が毎回用意する。
    grep -Fq 'mkdir -m 2750 /srv/chelly-workspaces/brainium' ${runnerCommand}

    python3 - \
      ${workbench.environment.etc."chelly-agent/chelly/config.toml".source} \
      ${workbench.environment.etc."chelly-agent/chelly/Dockerfile".source} <<'PY'
    import os
    import sys
    import tomllib

    with open(sys.argv[1], "rb") as source:
        config = tomllib.load(source)
    with open(sys.argv[2]) as source:
        assert source.readline().strip() == "FROM docker.io/library/debian:stable"
    mounts = config["additional_mounts"]
    assert "/nix:/nix:ro" in mounts, mounts
    assert "/run/chelly-nix:/nix/var/nix/daemon-socket:ro" in mounts, mounts
    assert "claude-state:/home/warashi/.claude" in mounts, mounts
    assert "copilot-state:/home/warashi/.copilot" in mounts, mounts
    # 本人の home は専用ユーザーに見せない。brainium は本人の clone ではなく
    # 専用領域の handoff clone を、コンテナ内では本人の CLAUDE.md と同じ path に見せる。
    assert not any(mount.startswith("/home/") for mount in mounts), mounts
    assert "/srv/chelly-workspaces/brainium:/home/warashi/ghq/github.com/Warashi" in mounts, mounts
    assert not any("brainium" in mount and not mount.startswith("/srv/chelly-workspaces/") for mount in mounts), mounts
    assert config["env_files"] == ["/run/secrets/chelly-agent-dotenv"], config["env_files"]
    assert config["inherit_env"] == ["COLORTERM", "TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION"]
    run = next(item["args"] for item in config["runtime_options"]
               if item["runtime"] == "podman" and item["subcommand"] == "run")
    assert "--userns=keep-id:uid=1000,gid=100" in run, run
    assert "--userns=keep-id" not in run, run
    assert "--env=CLAUDE_CONFIG_DIR=/home/warashi/.claude" in run, run
    assert "--env=IS_DEMO=1" in run, run
    assert "--pull=never" in run, run
    # 配布 bundle は /nix の read-only mount 越しに store path で渡す。
    config_env = [arg for arg in run if arg.startswith("--env=CHELLY_AGENT_CONFIG=")]
    assert len(config_env) == 1, run
    bundle = config_env[0].split("=", 2)[2]
    assert bundle.startswith("/nix/store/"), bundle
    for path in ("claude/CLAUDE.md", "claude/settings.json", "claude/output-styles/grilling.md",
                 "copilot/copilot-instructions.md", "copilot/settings.json",
                 "copilot/skills/pair-programming/SKILL.md"):
        assert os.path.isfile(os.path.join(bundle, path)), path
    PY
    touch "$out"
  ''

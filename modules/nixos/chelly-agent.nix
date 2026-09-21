{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.warashi.chelly-agent;
  username = "chelly-agent";
  home = "/var/lib/chelly-agent";
  workspaces = "/srv/chelly-workspaces";
  owner = config.warashi.username;
  ownerHome = config.users.users.${owner}.home;
  homeConfig = config.home-manager.users.${owner};
  chellyConfig = homeConfig.warashi.chelly;
  chelly = inputs.chelly.packages.${pkgs.stdenv.hostPlatform.system}.chelly;
  proxy = config.warashi.chelly-nix-proxy;
  # 本人の home-manager が host の ~/.claude と ~/.copilot に書くものと同じ生成物。
  # /nix は read-only で mount 済みなので store path をそのまま渡し、image の
  # entrypoint が volume へ写す。本人の実 home や認証状態は含まれない。
  agentConfig = pkgs.linkFarm "chelly-agent-config" [
    {
      name = "claude";
      path = homeConfig.warashi.claude.bundle;
    }
    {
      name = "copilot";
      path = homeConfig.warashi.copilot.bundle;
    }
  ];
  agentGroups = [
    config.users.users.${username}.group
  ]
  ++ config.users.users.${username}.extraGroups
  ++ lib.attrNames (lib.filterAttrs (_: group: lib.elem username group.members) config.users.groups);
  tomlFormat = pkgs.formats.toml { };
  configFile = tomlFormat.generate "chelly-agent.toml" {
    container_cmd = lib.getExe pkgs.podman;
    additional_mounts = [
      "/nix:/nix:ro"
      "${proxy.socket-dir}:/nix/var/nix/daemon-socket:ro"
      "${homeConfig.xdg.configFile."git/ignore".source}:/home/warashi/.config/git/ignore:ro"
      "claude-state:/home/warashi/.claude"
      "copilot-state:/home/warashi/.copilot"
      "go-cache:/home/warashi/.cache/go-build"
      "go-mod:/home/warashi/go/pkg/mod"
      "nix-cache:/home/warashi/.cache/nix"
    ];
    env_files = cfg.envfiles;
    inherit_env = [
      "COLORTERM"
      "TERM"
      "TERM_PROGRAM"
      "TERM_PROGRAM_VERSION"
    ];
    runtime_options = [
      {
        runtime = "podman";
        subcommand = "build";
        args = chellyConfig.runtime_options.podman.build;
      }
      {
        runtime = "podman";
        subcommand = "run";
        args =
          lib.filter (arg: !(lib.hasPrefix "--userns=" arg)) chellyConfig.runtime_options.podman.run
          ++ [
            "--env=CHELLY_AGENT_CONFIG=${agentConfig}"
            "--env=CLAUDE_CONFIG_DIR=/home/warashi/.claude"
            "--env=IS_DEMO=1"
            "--pull=never"
            "--userns=keep-id:uid=${toString chellyConfig.uid},gid=${toString chellyConfig.gid}"
          ];
      }
    ];
  };
  runner = pkgs.writeShellApplication {
    name = "chelly-agent-runner";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if [[ "$(id -un)" != ${lib.escapeShellArg username} ]]; then
        echo "chelly-agent: run through the chelly-agent launcher" >&2
        exit 1
      fi
      if [[ -r ${lib.escapeShellArg ownerHome} || -x ${lib.escapeShellArg ownerHome} ]]; then
        echo "chelly-agent: the primary user's home must not be accessible to the agent account" >&2
        exit 1
      fi
      case "$(pwd -P)" in
        ${workspaces}|${workspaces}/*) ;;
        *)
          echo "chelly-agent: start inside ${workspaces}, using an independent clone" >&2
          exit 1
          ;;
      esac
      runtime_dir="/run/user/$(id -u)"
      if [[ ! -d "$runtime_dir" ]]; then
        echo "chelly-agent: user runtime directory is missing; check the lingering user manager" >&2
        exit 1
      fi
      exec env -i \
        HOME=${lib.escapeShellArg home} \
        USER=${lib.escapeShellArg username} \
        LOGNAME=${lib.escapeShellArg username} \
        XDG_CONFIG_HOME=/etc/chelly-agent \
        XDG_DATA_HOME=${lib.escapeShellArg "${home}/.local/share"} \
        XDG_CACHE_HOME=${lib.escapeShellArg "${home}/.cache"} \
        XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
        PATH=${lib.escapeShellArg "${config.security.wrapperDir}:${
          lib.makeBinPath [
            pkgs.podman
            pkgs.gitMinimal
            pkgs.coreutils
            pkgs.util-linux
          ]
        }"} \
        LANG=C.UTF-8 \
        TERM="''${TERM:-dumb}" \
        COLORTERM="''${COLORTERM:-}" \
        TERM_PROGRAM="''${TERM_PROGRAM:-}" \
        TERM_PROGRAM_VERSION="''${TERM_PROGRAM_VERSION:-}" \
        ${lib.getExe' chelly "chelly"} "$@"
    '';
  };
  launcher = pkgs.writeShellScriptBin "chelly-agent" ''
    exec ${config.security.wrapperDir}/sudo -n -H -u ${username} -- ${lib.getExe runner} "$@"
  '';
in
{
  options.warashi.chelly-agent = {
    enable = lib.mkEnableOption "dedicated rootless chelly account";
    envfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Dedicated runtime envfiles readable by chelly-agent. Use decrypted secret paths,
        not Nix store files or the primary user's authentication state.
        No model credentials are supplied by default.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !(lib.any (
            user: user == username || user == "*" || lib.any (group: user == "@${group}") agentGroups
          ) config.nix.settings.trusted-users);
        message = "chelly-agent must not be a trusted Nix user or belong to a trusted Nix group";
      }
      {
        assertion = chellyConfig.enable && chellyConfig.nix-store == "host" && proxy.enable;
        message = "chelly-agent requires chelly with nix-store = host and the untrusted Nix proxy";
      }
      {
        assertion = lib.elem config.users.users.${owner}.homeMode [
          "700"
          "0700"
        ];
        message = "chelly-agent requires the primary user's homeMode to be 700";
      }
      {
        assertion = lib.all (
          path: lib.hasPrefix "/" path && !(lib.hasPrefix "${builtins.storeDir}/" path)
        ) cfg.envfiles;
        message = "chelly-agent envfiles must be absolute runtime paths outside the Nix store";
      }
    ];

    users.users.${username} = {
      isSystemUser = true;
      group = username;
      extraGroups = [ "chelly-workspaces" ];
      inherit home;
      homeMode = "700";
      createHome = true;
      linger = true;
      shell = pkgs.bashInteractive;
      autoSubUidGidRange = false;
      subUidRanges = [
        {
          startUid = 300000;
          count = 196608;
        }
      ];
      subGidRanges = [
        {
          startGid = 300000;
          count = 196608;
        }
      ];
    };
    users.groups.${username} = { };
    users.groups.chelly-workspaces = { };
    users.users.${owner}.extraGroups = [ "chelly-workspaces" ];
    systemd.tmpfiles.rules = [
      "d ${workspaces} 2750 ${username} chelly-workspaces - -"
    ];

    warashi.chelly-nix-proxy.socket-group = username;
    environment.etc = {
      "chelly-agent/chelly/config.toml".source = configFile;
      "chelly-agent/chelly/Dockerfile".source = chellyConfig.dockerfile;
    };
    environment.systemPackages = [ launcher ];
    security.sudo.extraRules = [
      {
        users = [ owner ];
        runAs = username;
        commands = [
          {
            command = lib.getExe runner;
            options = [
              "NOPASSWD"
              "NOSETENV"
            ];
          }
        ];
      }
    ];
  };
}

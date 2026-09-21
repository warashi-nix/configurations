{
  pkgs,
  lib,
  config,
  ...
}:
let
  settings-overrides = (pkgs.formats.json { }).generate "copilot-settings-override.json" {
    # keep-sorted start
    beep = false;
    colorMode = "default";
    continueOnAutoMode = true;
    copyOnSelect = true;
    experimental = false;
    includeCoAuthoredBy = true;
    mergeStrategy = "rebase";
    mouse = true;
    renderMarkdown = true;
    respectGitignore = false;
    stream = true;
    terminalProgress = true;
    theme = "auto";
    toolSearch = true;
    updateTerminalTitle = true;
    # keep-sorted end
    # keep-sorted start block=yes
    builtInAgents = {
      rubberDuck = true;
      rubberDuckAutoInvoke = true;
    };
    disabledSkills = [
      "customize-cloud-agent"
    ];
    footer = {
      # keep-sorted start
      showAgent = true;
      showAiUsed = true;
      showBranch = true;
      showCodeChanges = true;
      showContextWindow = true;
      showModelEffort = true;
      showQuota = true;
      showSandbox = true;
      showYolo = true;
      # keep-sorted end
    };
    ide = {
      autoConnect = false;
      openDiffOnEdit = false;
    };
    sandbox = {
      enabled = false;
    };
    tabs = {
      enabled = false;
    };
    # keep-sorted end
  };

  # 共通指示のあとに copilot 固有の指示を続ける。固有側は共通化しようがないものだけ。
  # grilling を末尾に置くのは、見出し付きの散文なので箇条書きの間に挟むと一覧が途切れるため。
  instructions = pkgs.writeText "copilot-instructions.md" (
    config.warashi.agent-instructions.text
    + builtins.readFile ./copilot-instructions.md
    + config.warashi.agent-instructions.grilling
  );

  # activation が ~/.copilot に書くものを、別環境へ持ち出せる形で束ねる。
  # skills は agent-skills が copilot 向けに選別した bundle をそのまま使う。
  skillsBundle = config.programs.agent-skills.targetBundlePaths.copilot or null;
  bundle = pkgs.runCommand "copilot-config-bundle" { } ''
    mkdir -p "$out"
    cp ${instructions} "$out/copilot-instructions.md"
    cp ${settings-overrides} "$out/settings.json"
    ${if skillsBundle == null then ''mkdir "$out/skills"'' else ''cp -r ${skillsBundle} "$out/skills"''}
  '';
in
{
  options.warashi.copilot.bundle = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    description = ''
      copilot-instructions.md、settings の override、skills を束ねた store path。
      activation が ~/.copilot に書く生成物と同じもので、認証状態や履歴は含まない。
    '';
  };

  config.warashi.copilot.bundle = bundle;

  config.home = {
    activation = {
      warashi-copilot-settings-merger = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        merge() {
        local f files=()
        for f in "$@"; do [[ -f $f ]] && files+=("$f"); done

        ${lib.getExe pkgs.jq} -n '
            def deep_merge($a; $b):
              if ($a | type == "object") and ($b | type == "object") then
                reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = deep_merge($a[$k]; $b[$k]))
              elif ($a | type == "array") and ($b | type == "array") then
                ($a + $b) | unique
              else
                $b
              end;
            reduce inputs as $item ({}; deep_merge(.; $item))
          ' "''${files[@]}"
        }

        run cp -af ${instructions} ${config.home.homeDirectory}/.copilot/copilot-instructions.md
        if [ -f ${config.home.homeDirectory}/.copilot/settings.json ]; then
        run cp -af ${config.home.homeDirectory}/.copilot/settings.json ${config.home.homeDirectory}/.copilot/settings.json.backup
        fi
        run merge ${config.home.homeDirectory}/.copilot/settings.json ${settings-overrides} > ${config.home.homeDirectory}/.copilot/settings.json.tmp
        run mv ${config.home.homeDirectory}/.copilot/settings.json.tmp ${config.home.homeDirectory}/.copilot/settings.json
      '';
    };
  };
}

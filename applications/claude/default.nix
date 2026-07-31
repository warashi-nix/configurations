{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.warashi.claude;
  jsonFormat = pkgs.formats.json { };
  # 既定値をまとめて mkDefault すると定義全体が捨てられて一部だけの上書きができなくなるため、葉ごとに mkDefault する
  mkDefaultRecursive = mapAttrsRecursive (_path: mkDefault);
  settingsFile = jsonFormat.generate "claude-settings-override.json" cfg.settings;
  memoryFile = pkgs.writeText "claude-memory.md" cfg.memory;

  settingsPath = "${cfg.configDir}/settings.json";
  extraSources = imap0 (
    index: source:
    source
    // {
      workPath = "${cfg.configDir}/settings.source-${toString index}.json";
    }
  ) cfg.extraSettingsSources;

  # jq のフィルタ結果は評価時に確定しないため、いったん作業ファイルに落としてから固定個数の入力としてマージする
  prepareExtraSource = source: ''
    if [ -f ${escapeShellArg source.path} ]; then
      run ${lib.getExe pkgs.jq} ${escapeShellArg source.filter} ${escapeShellArg source.path} \
        > ${escapeShellArg source.workPath}
    ${
      if source.optional then
        ''
          else
            run echo '{}' > ${escapeShellArg source.workPath}
          fi
        ''
      else
        ''
          else
            errorEcho "claude: settings source ${source.path} not found"
            exit 1
          fi
        ''
    }'';

  mergeInputs = [
    settingsPath
    (toString settingsFile)
  ]
  ++ map (source: source.workPath) extraSources;
  mergeExpr = concatStringsSep " * " (imap0 (index: _: ".[${toString index}]") mergeInputs);
in
{
  options.warashi.claude = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable warashi Claude Code configurations.";
    };
    configDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.claude";
      description = "Directory for Claude Code configurations (CLAUDE_CONFIG_DIR).";
    };
    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Settings merged into $CLAUDE_CONFIG_DIR/settings.json.
        既定値は葉ごとに mkDefault されているため、必要な項目だけを上書きできる。
      '';
    };
    memory = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Contents of $CLAUDE_CONFIG_DIR/CLAUDE.md.
        複数の定義は連結されるため、追記したい場合は mkAfter などを使う。
      '';
    };
    extraSettingsSources = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            path = mkOption {
              type = types.str;
              description = "Path to a JSON file merged into settings.json.";
            };
            filter = mkOption {
              type = types.str;
              default = ".";
              description = "jq filter applied to the source before merging.";
            };
            optional = mkOption {
              type = types.bool;
              default = false;
              description = "Skip the source instead of failing when the file does not exist.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Additional JSON sources merged into $CLAUDE_CONFIG_DIR/settings.json.
        既存の settings.json、warashi.claude.settings の順に重ねたあと、このリストの順で上書きされる。
      '';
    };
  };

  config = mkIf cfg.enable {
    warashi.claude = {
      memory = builtins.readFile ./CLAUDE.md;

      settings = mkDefaultRecursive {
        # keep-sorted start
        advisorModel = "fable";
        autoMemoryEnabled = false;
        cleanupPeriodDays = 10000;
        disableArtifact = true;
        disableBundledSkills = true;
        disableClaudeAiConnectors = true;
        disableDeepLinkRegistration = "disable";
        disableRemoteControl = true;
        outputStyle = "grilling";
        effortLevel = "low";
        enableArtifact = false;
        fastMode = false;
        feedbackSurveyRate = 0;
        language = "japanese";
        model = "sonnet";
        preferredNotifChannel = "terminal_bell";
        prefersReducedMotion = true;
        promptSuggestionEnabled = false;
        respondToBashCommands = false;
        showClearContextOnPlanAccept = true;
        spinnerTipsEnabled = false;
        terminalProgressBarEnabled = true;
        theme = "auto";
        tui = "fullscreen";
        useAutoModeDuringPlan = true;
        viewMode = "focus";
        # keep-sorted end
        # keep-sorted start block=yes
        enabledPlugins = {
          "gopls-lsp@claude-plugins-official" = true;
        };
        env = {
          # keep-sorted start
          CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
          CLAUDE_CODE_ENABLE_TELEMETRY = "1";
          # keep-sorted end
        };
        permissions = {
          defaultMode = "auto";
        };
        statusLine = {
          type = "command";
          command = ''
            jq -r '
              # --- 色 / ユーティリティ定義 ---------------------------------------
              def R:   "[0m";   # reset
              def AC:  "[36m";  # accent (cyan)
              def RED: "[31m";
              def YEL: "[33m";
              def GRN: "[32m";

              # 割合 $p を閾値 $hi / $mid で色分け
              def pcol($p; $hi; $mid): if $p>=$hi then RED elif $p>=$mid then YEL else GRN end;
              # 色付きパーセント表示（null はそのまま null）
              def cpct($p):  if $p==null then null else pcol($p; 90; 70) + "\($p|round)%" + R end;
              def cpctc($p): if $p==null then null else pcol($p; 70; 50) + "\($p|round)%" + R end;

              # 金額・経過時間の整形（null はそのまま null）
              def money($c):
                if $c==null then null
                else (($c*100)|round) as $cents
                  | "$" + (($cents/100)|floor|tostring) + "." + (("0"+(($cents%100)|tostring))|.[-2:])
                end;
              def dur($ms):
                if $ms==null then null
                else (($ms/1000)|floor) as $s | "\(($s/60)|floor)m \($s%60)s"
                end;

              # null なら null、そうでなければ接頭辞付き
              def tag($prefix; $v): if $v==null then null else $prefix + $v end;
              # null / 空文字を除いて結合
              def joinclean($sep): map(select(.!=null and .!="")) | join($sep);

              # --- 1行目セグメント: model / repo / context ----------------------
              ( .model.display_name? // null ) as $model |
              ( .effort.level? // null ) as $effort |
              ( if $model==null then null
                else AC + $model + R
                  + (if ($effort != null and $effort != "") then " "+$effort else "" end)
                end ) as $seg_model |

              ( (.workspace.repo | objects) // {} ) as $repo |
              ( if ($repo.owner!=null and $repo.name!=null) then "🌿 \($repo.owner)/\($repo.name)"
                elif (.worktree.branch? // null)!=null then "🌿 " + .worktree.branch
                elif (.workspace.git_worktree? // null)!=null then "🌿 " + .workspace.git_worktree
                else null end ) as $seg_repo |

              ( .agent.name? // null ) as $agent |
              ( .session_name? // null ) as $sess |
              ( .pr.number? // null ) as $pr |
              ( [ (if $agent!=null then "🤖 "+$agent else empty end),
                  ($sess // empty),
                  (if $pr!=null then "#\($pr)" else empty end) ]
                | if length>0 then join(" ") else null end ) as $seg_ctx |

              ( [ $seg_model, $seg_repo, $seg_ctx ] | joinclean("  ") ) as $line1 |

              # --- 2行目メトリクス: ctx / cost / dur / diff / rate --------------
              ( tag("🧠 "; cpctc(.context_window.used_percentage? // null)) ) as $m_ctx |
              ( tag("💰 "; money(.cost.total_cost_usd? // null)) ) as $m_cost |
              ( tag("⏱️ ";  dur(.cost.total_duration_ms? // null)) ) as $m_dur |
              ( (.cost.total_lines_added? // null) as $add |
                (.cost.total_lines_removed? // null) as $rem |
                if ($add==null and $rem==null) then null else "+\($add//0)/-\($rem//0)" end ) as $m_diff |
              ( .rate_limits.five_hour.used_percentage? // null ) as $r5 |
              ( .rate_limits.seven_day.used_percentage? // null ) as $r7 |
              ( [ (if $r5!=null then "5h "+cpct($r5) else empty end),
                  (if $r7!=null then "7d "+cpct($r7) else empty end) ]
                | if length>0 then "📊 " + join(" ") else null end ) as $m_rate |

              ( [ $m_ctx, $m_cost, $m_dur, $m_diff, $m_rate ] | joinclean("  |  ") ) as $line2 |

              # --- 最終結合 -----------------------------------------------------
              $line1 + "\n" + $line2
            ';
          '';
        };
        voice = {
          enabled = false;
        };
        # keep-sorted end
      };
    };

    home = {
      sessionVariables = {
        CLAUDE_CONFIG_DIR = cfg.configDir;
      };
      activation = {
        warashi-claude-code-configs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run mkdir -p ${escapeShellArg cfg.configDir}
          ${optionalString (cfg.memory != "") ''
            run ${lib.getExe pkgs.rsync} -a ${memoryFile} ${escapeShellArg "${cfg.configDir}/CLAUDE.md"}
          ''}

          run mkdir -p ${lib.escapeShellArg "${cfg.configDir}/output-styles"}
          run ${lib.getExe pkgs.rsync} -a ${./output-styles}/ ${lib.escapeShellArg "${cfg.configDir}/output-styles/"}

          if [ -f ${escapeShellArg settingsPath} ]; then
            run cp -af ${escapeShellArg settingsPath} ${escapeShellArg "${settingsPath}.backup"}
          else
            run echo '{}' > ${escapeShellArg settingsPath}
          fi
          ${concatMapStringsSep "\n" prepareExtraSource extraSources}
          run ${lib.getExe pkgs.jq} -s ${escapeShellArg mergeExpr} \
            ${concatMapStringsSep " \\\n  " escapeShellArg mergeInputs} \
            > ${escapeShellArg "${cfg.configDir}/settings.merged.json"}
          run mv ${escapeShellArg "${cfg.configDir}/settings.merged.json"} ${escapeShellArg settingsPath}
          ${optionalString (extraSources != [ ]) ''
            run rm -f ${concatMapStringsSep " " (source: escapeShellArg source.workPath) extraSources}
          ''}
        '';
      };
    };
  };
}

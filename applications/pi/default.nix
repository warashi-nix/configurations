{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.warashi.pi;
  jsonFormat = pkgs.formats.json { };
  modelsFile = jsonFormat.generate "pi-models.json" cfg.models;
  settingsFile = jsonFormat.generate "pi-settings.json" cfg.settings;
  instructionsFile = pkgs.writeText "pi-agents.md" config.warashi.agentInstructions.text;
  agentDir = "${config.home.homeDirectory}/.pi/agent";
  settingsPath = "${agentDir}/settings.json";
  mergedPath = "${agentDir}/settings.merged.json";
in
{
  options.warashi.pi = {
    enable = mkOption {
      type = types.bool;
      description = "Enable pi coding agent configuration.";
      default = true;
    };
    models = mkOption {
      type = jsonFormat.type;
      description = ''
        Contents of ~/.pi/agent/models.json.
        pi 自体はホストに入れず chelly のコンテナから使うが、設定の配置に pi は要らない。
        ホスト側に置くことで ~/.pi をコンテナへマウントでき、セッション履歴と認証が永続化できる。
      '';
      default = {
        providers = {
          athena = {
            # 実体の IP は Lima 固有なので、chelly の --add-host で athena-llama に注入する
            baseUrl = "http://athena-llama:11435/v1";
            api = "openai-completions";
            # llama-server は検証しないダミー。無いとモデルが選択肢に出ない
            apiKey = "llama-server";
            models = [
              {
                id = "ornith-1-5-9b";
                name = "Ornith 1.5 9B (athena)";
                reasoning = false;
                input = [ "text" ];
                contextWindow = 32768;
                maxTokens = 8192;
                cost = {
                  input = 0;
                  output = 0;
                  cacheRead = 0;
                  cacheWrite = 0;
                };
              }
            ];
          };
        };
      };
    };
    settings = mkOption {
      type = jsonFormat.type;
      description = ''
        Settings merged into ~/.pi/agent/settings.json.
        pi 自身もこのファイルに書く (analytics の ID、pi install したパッケージ) ため、
        models.json のように丸ごと置かず、claude と同じく既存へ重ねる。
      '';
      default = {
        # pi-acp は session/new の応答後に startup info を別送する。agent-shell は
        # その時点でプロンプトを出し終えており、read-only 領域への挿入で失敗する。
        # 中身は agent-shell が Available models / commands として自前で描画済み。
        quietStartup = true;
      };
    };
  };

  config = mkIf cfg.enable {
    home.activation.warashi-pi-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${escapeShellArg agentDir}
      # 同じディレクトリに pi が sessions/ と auth.json を書くため、ファイル単位でのみ配置する
      run ${lib.getExe pkgs.rsync} -a ${modelsFile} ${escapeShellArg "${agentDir}/models.json"}

      # pi は agentDir 直下を AGENTS.override.md -> AGENTS.md -> CLAUDE.md の順に探す。
      # chelly が ~/.pi をマウントするため、ここに置けばコンテナからも見える。
      run ${lib.getExe pkgs.rsync} -a ${instructionsFile} ${escapeShellArg "${agentDir}/AGENTS.md"}

      # settings.json だけ claude と同じく既存へ重ねるのは、models.json と違って
      # pi 自身もこのファイルに書く (analytics の ID、pi install したパッケージ) ため。
      if [ ! -f ${escapeShellArg settingsPath} ]; then
        run echo '{}' > ${escapeShellArg settingsPath}
      fi
      run ${lib.getExe pkgs.jq} -s '.[0] * .[1]' \
        ${escapeShellArg settingsPath} ${settingsFile} \
        > ${escapeShellArg mergedPath}
      run mv ${escapeShellArg mergedPath} ${escapeShellArg settingsPath}
    '';
  };
}

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
  agentDir = "${config.home.homeDirectory}/.pi/agent";
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
  };

  config = mkIf cfg.enable {
    home.activation.warashi-pi-models = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${escapeShellArg agentDir}
      # 同じディレクトリに pi が sessions/ と auth.json を書くため、ファイル単位でのみ配置する
      run ${lib.getExe pkgs.rsync} -a ${modelsFile} ${escapeShellArg "${agentDir}/models.json"}
    '';
  };
}

{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.warashi.agentInstructions;
in
{
  options.warashi.agentInstructions = {
    common = mkOption {
      type = types.lines;
      default = builtins.readFile ./AGENTS.md;
      description = ''
        Claude Code / Copilot CLI / pi agent に共通のグローバル指示。
        各エージェントのモジュールが text を自分の指示ファイルへ埋め込む。
      '';
    };
    brainium.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Add a instruction entry pointing task/knowledge management to ~/ghq/github.com/Warashi/brainium.
        brainium を持たない環境（このリポジトリを flake input として使う側）では false にして opt-out する。
      '';
    };
    text = mkOption {
      type = types.lines;
      readOnly = true;
      description = ''
        共通指示の最終形。各エージェントのモジュールはこれを参照する。
        エージェント固有の指示は共通化しようがないものだけを各モジュール側で追記する。
      '';
    };
  };

  # types.lines は定義同士を改行で連結するため、mkAfter で足すと箇条書きの間に空行が入る
  config.warashi.agentInstructions.text =
    cfg.common
    + optionalString cfg.brainium.enable "- タスク・ナレッジ管理には ~/ghq/github.com/Warashi/brainium を使う\n";
}

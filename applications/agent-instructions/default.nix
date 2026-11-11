{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.warashi.agent-instructions;
in
{
  options.warashi.agent-instructions = {
    common = mkOption {
      type = types.lines;
      default = builtins.readFile ./AGENTS.md;
      description = ''
        Claude Code / Copilot CLI に共通のグローバル指示。
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
    grillingBody = mkOption {
      type = types.lines;
      readOnly = true;
      default = builtins.readFile ./grilling.md;
      description = ''
        依頼の意図を掘る指示の本文。最上位エージェントだけに適用するため text には含めない。
        Claude Code は output-style、Copilot CLI は custom agent の本文として使う。
      '';
    };
  };

  # types.lines は定義同士を改行で連結するため、mkAfter で足すと箇条書きの間に空行が入る
  config.warashi.agent-instructions = {
    text =
      cfg.common
      + optionalString cfg.brainium.enable ''
        - タスク・ナレッジ管理には ~/ghq/github.com/Warashi/brainium を使う
        - brainium の task に着手したら、brainium の CLAUDE.md の規約に従って task の状態を更新する
        - brainium のファイルを書き換えたら、続きの作業に移る前に、触ったファイルだけを `git commit -- <file>` でコミットする
      '';
  };
}

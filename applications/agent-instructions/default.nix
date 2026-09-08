{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.warashi.agentInstructions;

  # Claude Code の output-style ファイルを正本にする。frontmatter は Claude 固有なので本文だけ使う
  grillingSource = ../claude/output-styles/grilling.md;
  grillingParts = splitString "\n---\n" (builtins.readFile grillingSource);
  grillingBody =
    assert assertMsg (
      length grillingParts == 2
    ) "${toString grillingSource}: frontmatter を 1 つだけ持つ前提が崩れている";
    elemAt grillingParts 1;
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
    grilling = mkOption {
      type = types.lines;
      readOnly = true;
      description = ''
        依頼の意図を掘る指示。Claude Code は output-style として持つため text には含めず、
        output-style を持たない Copilot CLI / pi が自分の指示ファイルへ text の後に埋め込む。
      '';
    };
  };

  # types.lines は定義同士を改行で連結するため、mkAfter で足すと箇条書きの間に空行が入る
  config.warashi.agentInstructions = {
    text =
      cfg.common
      + optionalString cfg.brainium.enable "- タスク・ナレッジ管理には ~/ghq/github.com/Warashi/brainium を使う\n";

    # 指示ファイルが subagent にも渡るかは Copilot CLI / pi とも docs に明記がないため、
    # 渡っても委譲先が質問で止まらないよう最上位エージェント限定と明示する
    grilling = ''

      # Output Style: grilling
      The following applies only to the top-level agent that converses directly with the user.
      A subagent working on a delegated task must not interview; it does the task as given.
    ''
    + grillingBody;
  };
}

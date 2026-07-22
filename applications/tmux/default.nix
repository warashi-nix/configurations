{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
let
  # agent はコンテナ内で動いていてプロセス名からは見えないため、
  # コンテナ実行コマンドかどうかで Coding Agent の pane を判定する
  agentCommandPattern = "^\\.?(chelly|podman|docker|nerdctl)(-wrapped)?$";

  # Coding Agent pane の入力待ち状態を判定して pane option @agent_state に保存する
  # コンテナ内の agent からは hook 等で tmux に状態を通知できないため、
  # ホスト側から読める pane の描画内容で判定する
  agentStateScan = pkgs.writeShellApplication {
    name = "tmux-agent-state-scan";
    runtimeInputs = [ config.programs.tmux.package ];
    text = ''
      # Claude Code / Codex / Copilot CLI とも作業中は中断キーの案内を表示し続ける
      # (Claude Code/Codex: "esc to interrupt"、Copilot: "(Esc to cancel)")
      # Claude Code の許可ダイアログ(=入力待ち)が小文字の "esc to cancel" を
      # 表示するため、大文字小文字を無視した判定にはできない
      busy_pattern='[Ee]sc to interrupt|\(Esc to cancel'
      tmux list-panes -a -f '#{m/r:${agentCommandPattern},#{pane_current_command}}' -F '#{pane_id}' |
        while read -r pane_id; do
          # pipefail 下で grep -q の早期終了が capture-pane を SIGPIPE で
          # 落とし誤判定になるため、パイプではなく変数に受けてから判定する
          content="$(tmux capture-pane -p -t "$pane_id")"
          state=waiting
          if grep -qE "$busy_pattern" <<<"$content"; then
            state=busy
          fi
          tmux set-option -p -t "$pane_id" @agent_state "$state"
        done
    '';
  };
in
{
  programs.tmux = {
    enable = true;
    shell = lib.getExe pkgs.fish;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    keyMode = "vi";
    mouse = true;
    shortcut = "g";
    terminal = "tmux-256color";
    sensibleOnTop = false;
    extraConfig = ''
      ${builtins.readFile ./extra-config.tmux}

      # C-w で pane 単位まで展開した一覧を開く
      # window 行には bell (🔔)、pane 行には Coding Agent の状態
      # (作業中 🤖 / 入力待ち 💬) と pane title を表示する
      # 入力待ちかどうかは choose-tree を開く直前にスキャンした @agent_state で表す
      bind C-w run-shell "${lib.getExe agentStateScan}" \; choose-tree -Z -F '#{?pane_format,#{?#{m/r:${agentCommandPattern},#{pane_current_command}},#{?#{==:#{@agent_state},waiting},💬 ,🤖 },}#{pane_current_command} "#{pane_title}",#{?window_format,#{window_name}#{window_flags}#{?window_bell_flag, 🔔,},#{session_windows} windows#{?session_attached, (attached),}}}'

      # ターミナルのライト/ダークテーマに追従する
      set-hook -g client-light-theme "source-file ${./modus-operandi.tmux}"
      set-hook -g client-dark-theme "source-file ${./modus-vivendi.tmux}"
    '';
  };
}

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
    runtimeInputs = [
      config.programs.tmux.package
      pkgs.coreutils
    ];
    text = ''
      # 「esc to interrupt」等の中断キー案内の文言では判定しない。
      # Claude Code の focus mode のように表示設定次第で案内が消える上、
      # CLI ごと・状態ごとに文言が揺れて追従しきれないため。
      # 代わりに、各 CLI とも作業中は画面の描画が更新され続けることを
      # 利用し、capture した内容に変化があるかどうかで判定する
      #
      # 1 回の capture 間隔をスピナー周期より長くするだけでは、
      # prefersReducedMotion 等でスピナーが止まっている場合に取りこぼす。
      # 作業中なら経過時間表示が 1 秒周期で更新されるため、観測窓を
      # 1 秒強 (0.2 秒 x 6 回) まで広げて polling し、変化を検出した
      # 時点で打ち切る
      scan_pane() {
        local pane_id=$1 before
        before="$(tmux capture-pane -p -t "$pane_id")"
        for _ in 1 2 3 4 5 6; do
          sleep 0.2
          if [ "$(tmux capture-pane -p -t "$pane_id")" != "$before" ]; then
            tmux set-option -p -t "$pane_id" @agent_state busy
            return
          fi
        done
        tmux set-option -p -t "$pane_id" @agent_state waiting
      }

      mapfile -t panes < <(
        tmux list-panes -a -f '#{m/r:${agentCommandPattern},#{pane_current_command}}' -F '#{pane_id}'
      )
      # pane 数に比例して choose-tree を開くまでの遅延が延びないよう、
      # pane ごとに並行で判定する
      for pane_id in "''${panes[@]}"; do
        scan_pane "$pane_id" &
      done
      wait
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

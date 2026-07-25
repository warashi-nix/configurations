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
      pkgs.gnugrep
    ];
    text = ''
      # 描画が更新され続けるかどうかでは判定しない。AskUserQuestion の
      # 選択 UI は点滅し続けるため入力待ちでも描画が止まらず、逆に
      # prefersReducedMotion + focus mode では作業中でも描画が数秒
      # 止まりうるので、更新の有無による判定は両方向に誤るため。
      # 代わりに、capture した画面にいま何が表示されているかで判定する
      #
      # - ダイアログ (AskUserQuestion・許可・trust) の表示中は入力待ち。
      #   各ダイアログは末尾にキー案内 (Claude Code は「Esc to cancel」、
      #   Copilot CLI は「esc to cancel」) を出し続ける
      # - 作業中は Claude Code が経過時間つきのスピナー行
      #   「✻ Xxx… (12s · ↓ 128 tokens · …)」を、Copilot CLI が中断案内
      #   「esc interrupt」を出し続ける。Claude Code の中断案内
      #   「esc to interrupt」は focus mode などの表示設定で消えるため、
      #   中断案内の文言だけには頼らず経過時間表示でも判定する
      # - どちらも表示されていなければ通常のプロンプト待ち
      scan_pane() {
        local pane_id=$1 content state
        content="$(tmux capture-pane -p -t "$pane_id")"
        if grep -qiE 'esc to cancel' <<<"$content"; then
          # ダイアログ表示中は turn の途中でも返事を待っているので、
          # 作業中の判定より先に拾う
          state=waiting
        elif grep -qiE '… \(([0-9]+[hm] )*[0-9]+s|esc (to )?interrupt' <<<"$content"; then
          state=busy
        else
          state=waiting
        fi
        tmux set-option -p -t "$pane_id" @agent_state "$state"
      }

      mapfile -t panes < <(
        tmux list-panes -a -f '#{m/r:${agentCommandPattern},#{pane_current_command}}' -F '#{pane_id}'
      )
      for pane_id in "''${panes[@]}"; do
        scan_pane "$pane_id"
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
      # (作業中 🤖 / 入力待ち 💬 / 未判定 ⏳) と pane title を表示する
      # スキャンは capture と grep だけで pane あたり数十 ms なので、
      # バックグラウンドにせず同期実行してから一覧を開く。一覧を開いた
      # 時点で全 pane の状態が確定していて、⏳ が出るのは一覧を開いた
      # まま新しい agent pane が現れたときだけ
      bind C-w run-shell "${lib.getExe agentStateScan}" \; choose-tree -Z -F '#{?pane_format,#{?#{m/r:${agentCommandPattern},#{pane_current_command}},#{?#{==:#{@agent_state},waiting},💬 ,#{?#{==:#{@agent_state},busy},🤖 ,⏳ }},}#{pane_current_command} "#{pane_title}",#{?window_format,#{window_name}#{window_flags}#{?window_bell_flag, 🔔,},#{session_windows} windows#{?session_attached, (attached),}}}'

      # ターミナルのライト/ダークテーマに追従する
      set-hook -g client-light-theme "source-file ${./modus-operandi.tmux}"
      set-hook -g client-dark-theme "source-file ${./modus-vivendi.tmux}"
    '';
  };
}

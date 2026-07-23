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
      # 利用し、capture した内容の変化で判定する
      #
      # ただし choose-tree の表示に伴う zoom や focus イベントでも
      # agent は入力待ちのまま画面を再描画しうるため、1 回の変化では
      # busy とせず、変化が 2 回観測されて初めて busy とする。
      # 静止判定の 1.2 秒 (0.2 秒 x 6 回) は、prefersReducedMotion で
      # スピナーが止まっていても 1 秒周期の経過時間表示の更新を
      # 取りこぼさない長さ。変化のたびに静止のカウントは取り直す
      scan_pane() {
        local pane_id=$1 before now changes=0 quiet=0

        # 前回の状態と混じらないように、最初に初期化する
        tmux set-option -p -t "$pane_id" @agent_state detecting

        # choose-tree 表示直後の再描画が基準の capture に混ざって
        # 変化 1 回ぶんを浪費しないよう、少し待ってから基準を取る
        sleep 0.4
        before="$(tmux capture-pane -p -t "$pane_id")"
        while :; do
          sleep 0.2
          now="$(tmux capture-pane -p -t "$pane_id")"
          if [ "$now" != "$before" ]; then
            before=$now
            changes=$((changes + 1))
            quiet=0
            if [ "$changes" -ge 2 ]; then
              tmux set-option -p -t "$pane_id" @agent_state busy
              return
            fi
          else
            quiet=$((quiet + 1))
            if [ "$quiet" -ge 6 ]; then
              tmux set-option -p -t "$pane_id" @agent_state waiting
              return
            fi
          fi
        done
      }

      mapfile -t panes < <(
        tmux list-panes -a -f '#{m/r:${agentCommandPattern},#{pane_current_command}}' -F '#{pane_id}'
      )
      # 逐次判定だと後ろの pane ほど結果の反映が pane 数に比例して
      # 遅れるため、pane ごとに並行で判定する
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
      # (作業中 🤖 / 入力待ち 💬 / 判定中 ⏳) と pane title を表示する
      # スキャン完了 (最大 3 秒程度) を待ってから一覧を開くと、単に
      # window/pane を切り替えたいだけのときに待たされてしまうため、
      # スキャンはバックグラウンドで実行して一覧は即座に開く。
      # choose-tree は表示中も server 状態の変化で項目の format を
      # 再評価する (tmux 3.7b で確認) ため、@agent_state の更新は
      # 開いたままの一覧に判定済みの pane から順に反映される
      bind C-w run-shell -b "${lib.getExe agentStateScan}" \; choose-tree -Z -F '#{?pane_format,#{?#{m/r:${agentCommandPattern},#{pane_current_command}},#{?#{==:#{@agent_state},waiting},💬 ,#{?#{==:#{@agent_state},busy},🤖 ,⏳ }},}#{pane_current_command} "#{pane_title}",#{?window_format,#{window_name}#{window_flags}#{?window_bell_flag, 🔔,},#{session_windows} windows#{?session_attached, (attached),}}}'

      # ターミナルのライト/ダークテーマに追従する
      set-hook -g client-light-theme "source-file ${./modus-operandi.tmux}"
      set-hook -g client-dark-theme "source-file ${./modus-vivendi.tmux}"
    '';
  };
}

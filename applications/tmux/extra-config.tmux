#!/usr/bin/env bash
# C-g 2回で C-g が送られるようにする
bind C-g send-prefix

# window numberが飛び飛びにならないようにする
set -g renumber-windows on

# status line を下部に配置する
set -g status-position bottom

# status line にセッション名・ホスト名・日時を表示する
set -g status-left " #S "
set -g status-left-length 0
set -g status-right " #h | %Y-%m-%d(%a) %H:%M "
set -g status-right-length 0
set -g status-justify absolute-centre

# title設定
set -g set-titles on
set -g set-titles-string '#T'

# terminal-features for xterm-ghostty
set -as terminal-features ',xterm-ghostty:256:clipboard:ccolour:cstyle:extkeys:focus:hyperlinks:margins:mouse:osc7:overline:progressbar:RGB:strikethrough:sync:title:usstyle'

# C-c でwindow作成
bind C-c new-window

# N / W / A で tn / tw / ta を popup から実行する
# shell の起動を待たずに済むよう、window ではなく popup を使う
bind N display-popup -E -w 80% -h 80% -T ' tn ' 'exec fish -c tn'
bind W display-popup -E -w 80% -h 80% -d "#{pane_current_path}" -T ' tw ' 'exec fish -c tw'
bind A display-popup -E -w 80% -h 80% -T ' ta ' 'exec fish -c ta'

# C-t で現在のwindowを一番左へ移動
bind C-t move-window -t 0

# h, v で画面分割
bind v split-window -h -c "#{pane_current_path}"
bind s split-window -v -c "#{pane_current_path}"

# H, V で pane 再配置
bind C-v select-layout main-vertical-mirrored
bind C-s select-layout main-horizontal
set -g main-pane-height "50%"
set -g main-pane-width "50%"

# C-o, M-o で分割した画面をRotate
bind -r C-o rotate-window -D
bind -r M-o rotate-window -U

# vim っぽいキーバインドでpaneを移動
bind -r C-h select-pane -L
bind -r C-j select-pane -D
bind -r C-k select-pane -U
bind -r C-l select-pane -R

# ベルの設定
set -g bell-action any
set -wg monitor-bell on
set -g visual-bell both

# OSC 52 clipboard
set -s set-clipboard on

# extended keys
set -s extended-keys on

# pane options
set -g allow-passthrough on
set -g allow-rename on
set -g allow-set-title on
set -g alternate-screen on

# other options
set -wg aggressive-resize on
set -wg automatic-rename on

set -wg popup-border-lines rounded
set -wg pane-scrollbars off

set -ga update-environment TERM
set -ga update-environment TERM_PROGRAM

# promptpane
bind C-q run-shell \
	'exec tmux split-window -v -l 5 \
		-c "#{pane_current_path}" \
		"exec vim promptpane://tmux/#{pane_id}"'

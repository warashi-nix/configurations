#!/usr/bin/env bash
# C-g 2回で C-g が送られるようにする
bind C-g send-prefix

# window numberが飛び飛びにならないようにする
set -g renumber-windows on

# status line を下部に配置する
set -g status-position bottom

# title設定
set -g set-titles on
set -g set-titles-string '#T'

# TrueColor 表示
# xterm-256color or xterm-ghostty
set -sa terminal-features ",xterm-*:RGB"

# C-w で window 一覧を開く
bind C-w choose-tree -Zw

# C-c でwindow作成
bind C-c new-window

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
bind -n M-q run-shell \
	'tmux split-window -v -l 10 \
		-c "#{pane_current_path}" \
		"vim promptpane://tmux/#{pane_id}"'

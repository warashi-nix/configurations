#!/usr/bin/env bash
# C-g 2回で C-g が送られるようにする
bind C-g send-prefix

# window numberが飛び飛びにならないようにする
set-option -g renumber-windows on

# status line を下部に配置する
set-option -g status-position bottom

# title設定
set-option -g set-titles on
set-option -g set-titles-string '#T'

# TrueColor 表示
# xterm-256color or xterm-ghostty
set-option -sa terminal-features ",xterm-*:RGB"

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
set-option -g main-pane-height "50%"
set-option -g main-pane-width "50%"

# C-o, M-o で分割した画面をRotate
bind -r C-o rotate-window -D
bind -r M-o rotate-window -U

# vim っぽいキーバインドでpaneを移動
bind -r C-h select-pane -L
bind -r C-j select-pane -D
bind -r C-k select-pane -U
bind -r C-l select-pane -R

# ベルの設定
set-option -g bell-action any
set-option -wg monitor-bell on
set-option -g visual-bell both

# OSC 52 clipboard
set-option -s set-clipboard on

# extended keys
set-option -s extended-keys on

# pane options
set-option -g allow-passthrough on
set-option -g allow-rename on
set-option -g allow-set-title on
set-option -g alternate-screen on

# other options
set-option -wg aggressive-resize on
set-option -wg automatic-rename on

set-option -wg popup-border-lines rounded
set-option -wg pane-scrollbars off

# promptpane
bind -n M-q run-shell \
	'tmux split-window -v -l 10 \
		-c "#{pane_current_path}" \
		"vim promptpane://tmux/#{pane_id}"'

;;; -*- lexical-binding: t -*-

(setq skk-server-host "localhost"
      skk-server-portnum 1178
      skk-server-report-response t
      skk-sticky-key ";"
      skk-dcomp-activate t)
(add-to-list 'skk-completion-prog-list
             '(skk-comp-by-server-completion) t)

;; TUI では skk-cursor が何もしないため、OSC 12 で端末にカーソル色を通知する
;; skk-cursor は color display でない端末では require 時に error を投げるので読み込まない

(defvar my/skk-tty-cursor-fallback-colors
  '((hiragana . "coral4")
    (katakana . "forestgreen")
    (jisx0208-latin . "orchid")
    (jisx0201 . "gold")
    (abbrev . "royalblue"))
  "TUI で入力モードごとに使うカーソル色。skk-cursor-*-color が束縛されていればそちらを優先する。")

(defun my/skk-tty-cursor-color-for (mode)
  (let ((var (intern (format "skk-cursor-%s-color" mode))))
    (or (and (boundp var) (symbol-value var))
        (cdr (assq mode my/skk-tty-cursor-fallback-colors)))))

(defun my/skk-tty-cursor-color ()
  (cond
   ((not (bound-and-true-p skk-mode)) nil)
   ((bound-and-true-p skk-abbrev-mode) (my/skk-tty-cursor-color-for 'abbrev))
   ((bound-and-true-p skk-jisx0208-latin-mode) (my/skk-tty-cursor-color-for 'jisx0208-latin))
   ((bound-and-true-p skk-jisx0201-mode) (my/skk-tty-cursor-color-for 'jisx0201))
   ((bound-and-true-p skk-katakana) (my/skk-tty-cursor-color-for 'katakana))
   ((bound-and-true-p skk-j-mode) (my/skk-tty-cursor-color-for 'hiragana))
   ;; latin モードの色が未設定なら端末既定のカーソル色に戻す
   (t (my/skk-tty-cursor-color-for 'latin))))

(defun my/skk-tty-cursor-spec (color)
  ;; 端末は X11 の色名を解釈できないので rgb: 表記に変換する
  (let ((values (and color (tty-color-standard-values color))))
    (when values
      (apply #'format "rgb:%04x/%04x/%04x" values))))

(defun my/skk-tty-cursor-apply ()
  (when (eq (framep (selected-frame)) t)
    (let* ((terminal (frame-terminal))
           (spec (my/skk-tty-cursor-spec (my/skk-tty-cursor-color))))
      (unless (equal spec (terminal-parameter terminal 'my/skk-tty-cursor-spec))
        (set-terminal-parameter terminal 'my/skk-tty-cursor-spec spec)
        (send-string-to-terminal
         (if spec (format "\e]12;%s\a" spec) "\e]112\a")
         terminal)))))

(defun my/skk-tty-cursor-apply-safe ()
  (condition-case nil
      (my/skk-tty-cursor-apply)
    (error nil)))

(defun my/skk-tty-cursor-reset-all ()
  (dolist (terminal (terminal-list))
    (when (and (eq (terminal-live-p terminal) t)
               (terminal-parameter terminal 'my/skk-tty-cursor-spec))
      (set-terminal-parameter terminal 'my/skk-tty-cursor-spec nil)
      (ignore-errors (send-string-to-terminal "\e]112\a" terminal)))))

(defun my/skk-tty-cursor-reset-terminal (terminal)
  (when (terminal-parameter terminal 'my/skk-tty-cursor-spec)
    (ignore-errors (send-string-to-terminal "\e]112\a" terminal))))

(add-hook 'delete-terminal-functions #'my/skk-tty-cursor-reset-terminal)
(add-hook 'post-command-hook #'my/skk-tty-cursor-apply-safe)
(add-hook 'kill-emacs-hook #'my/skk-tty-cursor-reset-all)

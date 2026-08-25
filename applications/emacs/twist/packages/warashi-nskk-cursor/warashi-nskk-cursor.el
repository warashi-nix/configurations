;;; warashi-nskk-cursor.el --- nskk のカーソル色をバッファに追従させる  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (nskk "0.3.0"))
;; Keywords: i18n, japanese, convenience

;;; Commentary:

;; nskk の `nskk-cursor-update' は状態が変わったときにしか呼ばれず、色はフレーム
;; 単位で持たれる。かなモードのバッファから別のバッファへ移っても誰も更新しない
;; ので、カーソルはかなの色のまま残る。TUI ではそもそも `set-cursor-color' が効か
;; ない。どちらも `post-command-hook' でカレントバッファの状態に同期させ、TUI では
;; OSC 12 で端末に通知する。
;;
;; nskk 本体のカーソル制御 (`nskk-use-color-cursor') は切って使う。復帰を担う
;; `nskk--cursor-color-restore' は、フレーム上に nskk バッファがひとつでも表示され
;; ていると復帰を拒む (`nskk--other-nskk-buffers-active-p') ため、分割ウィンドウで
;; 片方にかなモードのバッファが見えているとこの同期が効かなくなる。書き手をここ
;; 一本に絞る。
;;
;; 利用側で `warashi-nskk-cursor-apply-safe' を `post-command-hook' と window の
;; 変化を見る hook に、`warashi-nskk-cursor-tty-reset-terminal' を
;; `delete-terminal-functions' に、`warashi-nskk-cursor-tty-reset-all' を
;; `kill-emacs-hook' に登録する。

;;; Code:

;; nskk を実行時に require しないのは、この同期が startup 時から
;; post-command-hook に居座る一方、日本語を打たない日もあるため。
(eval-when-compile (require 'nskk))

(defun warashi-nskk-cursor-color ()
  "選択中のバッファに対応するカーソル色を返す。nskk が居なければ nil。"
  (and (bound-and-true-p nskk-mode)
       (bound-and-true-p nskk-current-state)
       (fboundp 'nskk--cursor-with-color)
       (nskk--cursor-with-color (nskk-state-mode nskk-current-state))))

(defun warashi-nskk-cursor--apply-gui (color)
  "GUI フレームのカーソル色を COLOR にする。COLOR が nil なら元に戻す。"
  ;; 退避値ではなく frame-parameter の現在値と比べる。テーマ変更などで外か
  ;; ら色が変わっても次のコマンドで自己修復させたい
  (let* ((frame (selected-frame))
         (original (frame-parameter frame 'warashi-nskk-cursor-original)))
    (cond
     (color
      ;; cursor-color が未設定のフレームでは nil を t で記録する。nil は
      ;; 「退避していない」の意味に使っているため
      (unless original
        (set-frame-parameter frame 'warashi-nskk-cursor-original
                             (or (frame-parameter frame 'cursor-color) t)))
      (unless (equal color (frame-parameter frame 'cursor-color))
        (set-frame-parameter frame 'cursor-color color)))
     (original
      (let ((restored (unless (eq original t) original)))
        (unless (equal restored (frame-parameter frame 'cursor-color))
          (set-frame-parameter frame 'cursor-color restored))
        (set-frame-parameter frame 'warashi-nskk-cursor-original nil))))))

(defun warashi-nskk-cursor--tty-spec (color)
  "COLOR を OSC 12 に載せる rgb: 表記へ変換する。"
  ;; 端末は X11 の色名を解釈できないので rgb: 表記に変換する
  (let ((values (and color (tty-color-standard-values color))))
    (when values
      (apply #'format "rgb:%04x/%04x/%04x" values))))

(defun warashi-nskk-cursor--apply-tty (color)
  "端末のカーソル色を COLOR にする。COLOR が nil なら元に戻す。"
  (let* ((terminal (frame-terminal))
         (spec (warashi-nskk-cursor--tty-spec color)))
    (unless (equal spec (terminal-parameter terminal 'warashi-nskk-cursor-tty-spec))
      (set-terminal-parameter terminal 'warashi-nskk-cursor-tty-spec spec)
      (send-string-to-terminal
       (if spec (format "\e]12;%s\a" spec) "\e]112\a")
       terminal))))

(defun warashi-nskk-cursor-apply ()
  "選択ウィンドウのバッファの状態にカーソル色を合わせる。"
  ;; カレントバッファではなく選択ウィンドウのバッファを見る。カーソルが実
  ;; 際に居るのはそこで、window の変化 hook から呼ばれるときは current
  ;; buffer が一致している保証がない
  (let ((color (with-current-buffer (window-buffer (selected-window))
                 (warashi-nskk-cursor-color))))
    (cond
     ((display-graphic-p) (warashi-nskk-cursor--apply-gui color))
     ((eq (framep (selected-frame)) t) (warashi-nskk-cursor--apply-tty color)))))

(defun warashi-nskk-cursor-apply-safe (&rest _)
  "`warashi-nskk-cursor-apply' を hook から安全に呼ぶ。"
  ;; エラーを握り潰すのは、post-command-hook で失敗すると Emacs が hook から
  ;; 関数を外してしまい、以後どのバッファでも同期が止まるため。
  (condition-case nil
      (warashi-nskk-cursor-apply)
    (error nil)))

(defun warashi-nskk-cursor-tty-reset-all ()
  "色を触った端末を全て元に戻す。"
  (dolist (terminal (terminal-list))
    (when (and (eq (terminal-live-p terminal) t)
               (terminal-parameter terminal 'warashi-nskk-cursor-tty-spec))
      (set-terminal-parameter terminal 'warashi-nskk-cursor-tty-spec nil)
      (ignore-errors (send-string-to-terminal "\e]112\a" terminal)))))

(defun warashi-nskk-cursor-tty-reset-terminal (terminal)
  "TERMINAL の色を元に戻す。"
  (when (terminal-parameter terminal 'warashi-nskk-cursor-tty-spec)
    (ignore-errors (send-string-to-terminal "\e]112\a" terminal))))

(provide 'warashi-nskk-cursor)
;;; warashi-nskk-cursor.el ends here

;;; warashi-nskk-map.el --- nskk-mode-map を打鍵条件付きに包む  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (nskk "0.3.0") (warashi-nskk-im "0.1.0"))
;; Keywords: i18n, japanese, convenience

;;; Commentary:

;; minor-mode map は major-mode map より先に引かれるので、`nskk-mode' が入った
;; バッファでは q / l / x / RET などが dired や magit の単キーを潰す。
;; `nskk-mode-map' の各バインドを `:filter' 付きに包み直し、nskk が打鍵を取る
;; べきときだけ有効にする。
;;
;; 判定は `warashi-nskk-im' と共有する。input-method-function 側とキーマップ側で
;; 条件がずれると、read-only バッファで a は major mode に降りるのに q だけ nskk
;; に吸われる、という不整合が出る。
;;
;; 利用側で `nskk' のロード後に `warashi-nskk-map-wrap' を呼び、
;; `warashi-nskk-map-restore-bound-commands' を `nskk-mode-hook' に登録する。

;;; Code:

;; 包む対象は nskk のロード後にしか無い。呼び出し側が with-eval-after-load で
;; 順序を担保する。
(eval-when-compile (require 'nskk))
(require 'warashi-nskk-im)

(defvar warashi-nskk-map--originals nil
  "包む前の `nskk-mode-map' のバインド。(KEY . COMMAND) の alist。")

(defun warashi-nskk-map--active-p ()
  "現在の打鍵を nskk が取るべきなら non-nil。
`warashi-nskk-im-translate' が合成イベントに差し替える条件と同じものを
キーマップ探索の側でも使う。両者がずれると、read-only バッファで a は
major mode に降りるのに q だけ nskk に吸われる、という不整合が出る。"
  (and (warashi-nskk-im--consumes-typing-p)
       (not (warashi-nskk-im--defer-p last-input-event))))

(defun warashi-nskk-map--filter (cmd)
  "CMD を `warashi-nskk-map--active-p' のときだけ有効にする `:filter'。"
  (and (warashi-nskk-map--active-p) cmd))

(defun warashi-nskk-map--mode-switch-filter (cmd)
  "CMD をモードに依らず有効にする `:filter'。
C-j は ascii モードから かなモードへ戻る唯一の打鍵なので、モード条件で
塞ぐと日本語入力に入る手段が無くなる。read-only や transient map のとき
だけ major mode に譲る。"
  (and (not (warashi-nskk-im--defer-p last-input-event)) cmd))

(defun warashi-nskk-map--wrap-binding (key cmd filter)
  "KEY の CMD を FILTER 付きに包み直し、元のバインドを控える。"
  (push (cons key cmd) warashi-nskk-map--originals)
  (define-key nskk-mode-map key
              `(menu-item "" ,cmd :filter ,filter)))

(defun warashi-nskk-map-wrap ()
  "`nskk-mode-map' の各バインドを `:filter' 付きに包み直す。
minor-mode map は major-mode map より先に引かれるので、nskk-mode が入った
バッファでは q / l / x / RET などが dired や magit の単キーを潰す。
ascii モードではハンドラが `self-insert-command' に落ちるため、read-only
バッファでは quit する代わりに \"Buffer is read-only\" になる。"
  (let (entries)
    (map-keymap (lambda (event binding) (push (cons event binding) entries))
                nskk-mode-map)
    (pcase-dolist (`(,event . ,binding) entries)
      (cond
       ;; C-x C-j はモードを問わず切替の入口として生かす。
       ((eq event ?\C-x) nil)
       ((eq event ?\C-j)
        (warashi-nskk-map--wrap-binding
         (vector event) binding #'warashi-nskk-map--mode-switch-filter))
       ((eq event 'remap)
        (let (remaps)
          (map-keymap (lambda (cmd sub) (push (cons cmd sub) remaps)) binding)
          (pcase-dolist (`(,cmd . ,sub) remaps)
            (when (commandp sub)
              (warashi-nskk-map--wrap-binding
               (vector 'remap cmd) sub #'warashi-nskk-map--filter)))))
       ((commandp binding)
        (warashi-nskk-map--wrap-binding
         (vector event) binding #'warashi-nskk-map--filter))))))

(defun warashi-nskk-map-restore-bound-commands ()
  "包んだせいで漏れたコマンドを `nskk--bound-commands' に足し戻す。
nskk は `accessible-keymaps' と `commandp' で ▽ 中の point-escape ガード用の
コマンド一覧を作る。menu-item は `commandp' が nil を返すので、放っておくと
nskk 自身のハンドラが「知らないコマンド」扱いになって確定が走ってしまう。"
  (setq nskk--bound-commands
        (append (mapcar #'cdr warashi-nskk-map--originals) nskk--bound-commands)))


(provide 'warashi-nskk-map)
;;; warashi-nskk-map.el ends here

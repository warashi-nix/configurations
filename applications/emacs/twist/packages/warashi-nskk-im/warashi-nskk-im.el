;;; warashi-nskk-im.el --- input-method-function 経由で nskk に打鍵を渡す  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (nskk "0.3.0"))
;; Keywords: i18n, japanese, convenience

;;; Commentary:

;; `nskk-mode-map' は打鍵の取り込みを `<remap> <self-insert-command>' 一本に
;; 頼っているが、remap は「そのキーが解決したコマンド」に引かれるため、major
;; mode が印字可能キーを直接バインドしていると nskk まで届かない。agent-shell
;; の n がその例で、konnkai が こnnかい になる。dired や magit でも同種の衝突が
;; 起きうる。
;;
;; `input-method-function' はキーマップ探索より手前で呼ばれるので、ここで文字を
;; nskk 専用の合成イベントに差し替えてしまえば、どの major mode とも衝突しない。
;; quail のように自前の read ループは持たない。ループを持つとコマンドが走らなく
;; なり、`post-command-hook' に依存する corfu と capf が死ぬため。合成イベントを
;; `nskk-mode-map' 側で本来のハンドラに橋渡しする形なら、`this-command' が
;; `nskk-self-insert' のまま残るので corfu 連携はそのまま動く。
;;
;; 利用側で `warashi-nskk-im-install-dispatch-bindings' を `nskk-mode-map' の
;; 用意できたところで呼び、`warashi-nskk-im-setup' を `nskk-mode-hook' に登録
;; する。`japanese-nskk' として入力メソッド登録するなら
;; `warashi-nskk-im-activate' を `register-input-method' に渡す。

;;; Code:

(require 'cl-lib)
;; nskk を実行時に require しないのは、この経路が startup 時から
;; input-method-function に居座る一方、日本語を打たない日もあるため。compile 時
;; だけ読ませ、load は nskk-mode が入るまで遅らせる。
(eval-when-compile (require 'nskk))

(defconst warashi-nskk-im--event-prefix "warashi-nskk-key-")

(defconst warashi-nskk-im--char-min 32
  "合成イベントに差し替える文字の下限。")

(defconst warashi-nskk-im--char-max 126
  "合成イベントに差し替える文字の上限。")

(defun warashi-nskk-im--event (char)
  "CHAR に対応する合成イベントのシンボルを返す。"
  (intern (concat warashi-nskk-im--event-prefix (number-to-string char))))

(defun warashi-nskk-im--event-char (event)
  "合成イベント EVENT の元の文字を返す。合成イベントでなければ nil。"
  (when (symbolp event)
    (let ((name (symbol-name event)))
      ;; 数字であることまで見るのは、string-to-number が数字でない綴りに対して
      ;; 0 を返し、char 0 の合成イベントと区別できなくなるため。
      (when (string-match (concat "\\`" (regexp-quote warashi-nskk-im--event-prefix)
                                  "\\([0-9]+\\)\\'")
                          name)
        (string-to-number (match-string 1 name))))))

(defun warashi-nskk-im--consumes-typing-p ()
  "現在のバッファで nskk が打鍵を消費するなら non-nil。
ascii と latin だけが `input-route/2' で `insert-direct' を返す。"
  (and (bound-and-true-p nskk-mode)
       (bound-and-true-p nskk-current-state)
       (not (eq (nskk-prolog-query-value
                 `(input-route ,(nskk-state-get-mode) ,'\?action) '\?action)
                'insert-direct))))

(defun warashi-nskk-im--dispatch ()
  "合成イベントを `nskk-mode-map' 本来のハンドラへ橋渡しする。"
  (interactive)
  (when-let* ((char (warashi-nskk-im--event-char last-command-event)))
    (let ((cmd (or (keymap-lookup nskk-mode-map (single-key-description char))
                   #'nskk-self-insert))
          (last-command-event char))
      ;; corfu-auto は corfu-auto-commands を this-command で照合するので、
      ;; 橋渡し役ではなく実際に走るコマンド名を残す。
      (setq this-command cmd)
      (call-interactively cmd))))

(defun warashi-nskk-im--defer-p (key)
  "KEY を差し替えずにそのまま流すべきなら non-nil。
`quail-input-method' 冒頭の判定を写したもの。read-only な領域では
major mode の単キーコマンド (agent-shell の出力領域の n など) を残す。
transient map が KEY を握っているときに差し替えると、C-u 5 の 5 が
`universal-argument-map' に届かず前置引数が壊れる。"
  (or (and (or buffer-read-only
               (and (get-char-property (point) 'read-only)
                    (get-char-property (point) 'front-sticky)))
           (not (or inhibit-read-only
                    (get-char-property (point) 'inhibit-read-only))))
      (and overriding-terminal-local-map
           (lookup-key overriding-terminal-local-map (vector key)))
      overriding-local-map))

(defun warashi-nskk-im-translate (key)
  "KEY を nskk 専用の合成イベントに差し替える。
nskk が打鍵を消費しないモード (ascii/latin) では KEY をそのまま返し、
major mode の単キーコマンドを潰さない。"
  (if (and (integerp key)
           (<= warashi-nskk-im--char-min key)
           (<= key warashi-nskk-im--char-max)
           (warashi-nskk-im--consumes-typing-p)
           (not (warashi-nskk-im--defer-p key)))
      (list (warashi-nskk-im--event key))
    (list key)))

(defun warashi-nskk-im-install-dispatch-bindings ()
  "合成イベントの橋渡しを `nskk-mode-map' に入れる。
合成イベントは他のどのマップにも存在しないので、`nskk-mode-map' に直接
置いても既存のキーとは衝突しない。合成イベントは翻訳が走ったときしか
届かないので、`warashi-nskk-map' 側では包まない。"
  (cl-loop for char from warashi-nskk-im--char-min to warashi-nskk-im--char-max
           do (keymap-set nskk-mode-map
                          (key-description (vector (warashi-nskk-im--event char)))
                          #'warashi-nskk-im--dispatch)))

(defun warashi-nskk-im-setup ()
  "現在のバッファで合成イベント経路を有効にする。"
  (setq-local input-method-function #'warashi-nskk-im-translate))

(defun warashi-nskk-im-activate (&optional _name)
  "`japanese-nskk' 入力メソッドとして nskk を有効にする。"
  (setq deactivate-current-input-method-function #'warashi-nskk-im-deactivate)
  (nskk-global-mode 1))

(defun warashi-nskk-im-deactivate ()
  "`japanese-nskk' 入力メソッドを無効にする。"
  (nskk-global-mode -1))

(provide 'warashi-nskk-im)
;;; warashi-nskk-im.el ends here

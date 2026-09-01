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
;; 有効化は `nskk-global-mode' ではなくバッファローカルな `nskk-mode' で行う。
;; 状態表示を `current-input-method-title' に載せて mode-line の左端に出すには、
;; 有効・無効・状態・表示が同じバッファローカルな一点から決まっている必要がある。
;;
;; 利用側で `warashi-nskk-im-install-dispatch-bindings' を `nskk-mode-map' の
;; 用意できたところで呼び、`warashi-nskk-im-setup' と
;; `warashi-nskk-im-sync-title' を `nskk-mode-hook' に登録し、
;; `warashi-nskk-im-install-title-advice' を nskk のロード後に呼ぶ。
;; `japanese-nskk' として入力メソッド登録するなら
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


(defconst warashi-nskk-im--title-mode-width 4
  "状態の文字列に取る桁数。かな カナ 全英 の全角 2 文字ぶん。")

(defun warashi-nskk-im--title ()
  "mode-line の左端に置く状態表示を組み立てて返す。"
  ;; 飾りを `nskk-modeline-format' ではなくここで付けるのは、桁を揃える -
  ;; の数が状態ごとに変わるため。書式文字列一本では表現できない。
  (let* ((nskk-modeline-format "%m")
         (mode (substring-no-properties (nskk-modeline-indicator)))
         ;; 半角の SKK や aA を右に寄せる。左に足すのは、状態が変わっても
         ;; 文字列の右端 (: の隣) が動かないようにするため。
         (pad (max 0 (- warashi-nskk-im--title-mode-width (string-width mode)))))
    ;; 先頭の - が 1 つなのは、mode-line-front-space の - がこの手前に出るため。
    ;; ddskk の見た目 (--かな:-) と桁が揃う。
    (concat "-" (make-string pad ?-) mode ":-")))

(defun warashi-nskk-im-sync-title ()
  "nskk の状態表示を `current-input-method-title' に写す。
`mode-line-mule-info' がこの変数を mode-line の左端に描くので、状態は
minor-mode 欄ではなくそこに出る。"
  ;; 色は落とす。ddskk も端末では色を付けず (skk-indicator-use-cursor-color が
  ;; window-system 依存)、GUI で付ける色はカーソル色そのもの。こちらではカーソル
  ;; 色の同期を warashi-nskk-cursor が担っているので、mode-line 側は素で置く。
  ;;
  ;; `(:eval ...)' 構造ではなく確定した文字列を入れる。状態が変わる場所は nskk
  ;; 側で一点に集まっていて、再描画のたびに評価させる必要がない。
  (cond
   ((bound-and-true-p nskk-mode)
    (setq current-input-method-title (warashi-nskk-im--title)))
   ;; `nskk-toggle-mode' を直に叩くと `deactivate-input-method' を通らずに
   ;; nskk-mode だけを落とす。`current-input-method' は立ったままなので、
   ;; 畳まないと打鍵は ascii なのに左端は かな のまま固まる。
   ((equal current-input-method "japanese-nskk")
    (setq current-input-method-title nil))))

(defun warashi-nskk-im-install-title-advice ()
  "状態が変わるたびに表示を写すようにする。"
  ;; 状態遷移の口は複数あるが、どれも最後に `nskk-modeline-update' を通る。
  ;; 個々のコマンドではなくここ一点に付ける。
  (advice-add 'nskk-modeline-update :after #'warashi-nskk-im-sync-title))

(defun warashi-nskk-im-activate (&optional _name)
  "`japanese-nskk' 入力メソッドとして nskk を有効にする。"
  (setq deactivate-current-input-method-function #'warashi-nskk-im-deactivate)
  (nskk-mode 1)
  ;; 有効化はそのまま `nskk-state-default-mode' (ascii) に落ちる。C-\ は
  ;; 日本語を打ち始める操作なので、かなまで進めてしまう。
  (nskk-set-mode-hiragana)
  ;; `activate-input-method' は呼び出し後に title が文字列でなければ登録時の
  ;; TITLE で埋める。ここで入れておけば上書きされない。
  (warashi-nskk-im-sync-title))

(defun warashi-nskk-im-deactivate ()
  "`japanese-nskk' 入力メソッドを無効にする。"
  (nskk-mode -1))

(provide 'warashi-nskk-im)
;;; warashi-nskk-im.el ends here

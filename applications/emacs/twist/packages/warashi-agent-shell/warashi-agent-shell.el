;;; warashi-agent-shell.el --- agent-shell の起動と表示まわり  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (agent-shell "0.1.0"))
;; Keywords: convenience, tools

;;; Commentary:

;; agent-shell に足している三つのこと。
;;
;; - 単キーコマンドに入力メソッドを奪わせない。`agent-shell-mode-map' は n p r
;;   + - 0 を素のキーで握っており、プロンプト上ではそれぞれのコマンドが
;;   `self-insert-command' を直接呼ぶ。直接呼び出しは `nskk-mode-map' の
;;   `<remap> <self-insert-command>' を通らないので、konnkai が こnnかい になる。
;; - model と effort を固定した起動コマンド。effort は agent config に設定点が
;;   無く、session 確立後に ACP の config option として送るしかない。
;; - session の累積コストを context usage indicator の隣に常設する。
;;
;; 利用側で `warashi-agent-shell-install-self-insert-advice' と
;; `warashi-agent-shell-install-cost-indicator' を agent-shell のロード後に呼び、
;; `warashi-agent-shell--apply-thought-level' を `agent-shell-mode-hook' に登録
;; する。起動コマンドは `warashi-agent-shell-define-claude-variants' で作る。

;;; Code:

(require 'map)
;; agent-shell を実行時に require しないのは、起動コマンドを呼ぶまで agent-shell
;; を読む必要が無いため。compile 時だけ読ませる。
(eval-when-compile (require 'agent-shell))

;;;; 単キーコマンドに入力メソッドを奪わせない

(defconst warashi-agent-shell-self-insert-commands
  '(agent-shell-next-item
    agent-shell-previous-item
    agent-shell-quote-region
    agent-shell-image-scale-increase
    agent-shell-image-scale-decrease
    agent-shell-image-scale-reset)
  "プロンプト上で `self-insert-command' を直接呼ぶ agent-shell のコマンド。")

(defun warashi-agent-shell--self-insert-via-remap (fn &rest args)
  ;; remap が無いときは素通しする。入力メソッドを使っていない状態での挙動を
  ;; 変えないため。
  (if-let* ((_ (agent-shell--typing-at-prompt-p))
            (remapped (command-remapping #'self-insert-command)))
      (call-interactively remapped)
    (apply fn args)))

(defun warashi-agent-shell-install-self-insert-advice ()
  "`warashi-agent-shell-self-insert-commands' を remap 経由に差し替える。"
  (dolist (fn warashi-agent-shell-self-insert-commands)
    (advice-add fn :around #'warashi-agent-shell--self-insert-via-remap)))

;;;; 起動コマンド

(defun warashi-agent-shell--apply-thought-level ()
  "agent config に載せた thought level (effort) を新しい shell に適用する。"
  ;; effort は agent-shell の agent config に設定点が無く、session 確立後に
  ;; ACP の config option として送るしかない。claude-agent-acp は初期 effort を
  ;; settings ファイルからしか読まないため、_meta 経由では指定できない。
  (when-let* ((config (alist-get :agent-config (agent-shell--state)))
              (level (alist-get :warashi-thought-level config)))
    (agent-shell-subscribe-to
     :shell-buffer (current-buffer)
     :event 'init-finished
     :on-event
     (lambda (_event)
       (agent-shell--config-option-set-thought-level-id
        :thought-level-id level
        :on-failure (lambda (acp-error _raw-message)
                      (message "Failed to set thought level %s: %s" level acp-error)))))))

(defun warashi-agent-shell--start-claude (model-id thought-level)
  "MODEL-ID と THOUGHT-LEVEL を指定して Claude agent-shell を起動する。"
  (require 'agent-shell-anthropic)
  (let ((config (agent-shell-anthropic-make-claude-code-config)))
    ;; :default-model-id は session 確立後に funcall されるので、動的束縛では
    ;; なく MODEL-ID を lexical に閉じ込めた関数へ差し替える。
    (setcdr (assq :default-model-id config) (lambda () model-id))
    ;; thought level を動的束縛で渡さないのは、`agent-shell-mode-hook' が
    ;; `agent-shell--dwim' の動的エクステント内で走るとは限らないため。
    ;; config は state の :agent-config に保存されるので、そこから読ませる。
    (push (cons :warashi-thought-level thought-level) config)
    (agent-shell--dwim :config config :new-shell t)))

(defmacro warashi-agent-shell-define-claude-variants (&rest variants)
  "VARIANTS から Claude agent-shell の起動コマンドを定義する。
VARIANTS の各要素は (NAME MODEL-ID THOUGHT-LEVEL)。NAME ごとに
`warashi-agent-shell-claude-NAME' と、eshell から短い名前で呼ぶための
`eshell/claude-NAME' を生成する。"
  ;; 一覧を defconst に置いてマクロから参照しないのは、byte-compile 時に
  ;; defconst が評価されず、マクロ展開時に void-variable になるため。
  `(progn
     ,@(mapcan
        (pcase-lambda (`(,name ,model-id ,thought-level))
          (let ((fn (intern (format "warashi-agent-shell-claude-%s" name)))
                (eshell-fn (intern (format "eshell/claude-%s" name))))
            (list
             `(defun ,fn ()
                ,(format "Claude agent-shell を model %s / effort %s で起動する。"
                         model-id thought-level)
                (interactive)
                (warashi-agent-shell--start-claude ,model-id ,thought-level))
             `(defun ,eshell-fn (&rest _args)
                ,(format "eshell から `%s' を起動する。" fn)
                (,fn)))))
        variants)))

;;;; コスト表示

(defun warashi-agent-shell--cost-indicator ()
  "session の累積コストを表示用の文字列で返す。"
  ;; state を読むのに内部関数を使うのは、usage を取得する公開 API が無いため。
  (when-let* ((usage (map-elt (agent-shell--state) :usage))
              (amount (map-elt usage :cost-amount))
              ((> amount 0)))
    (let ((currency (map-elt usage :cost-currency)))
      ;; USD を $ に畳むのは、幅の限られる header で 2 文字を惜しむため。
      (format "%s%.2f" (if (member currency '(nil "USD")) "$" currency) amount))))

(defun warashi-agent-shell--append-cost-indicator (indicator)
  "context usage INDICATOR の後ろに cost を足す。"
  ;; mode-line ではなく context indicator に相乗りするのは、tty では
  ;; `agent-shell-header-style' が text になり、`agent-shell--mode-line-format'
  ;; が nil を返して情報が header-line 側にしか出ないため。
  ;; indicator が nil のときに cost だけ返さないのは、context 未取得の段階で
  ;; header に単独の数字が現れると何の値か分からないため。
  (if-let* ((indicator)
            (cost (warashi-agent-shell--cost-indicator)))
      (concat indicator " " cost)
    indicator))

(defun warashi-agent-shell-install-cost-indicator ()
  "context usage indicator に cost を相乗りさせる。"
  (advice-add 'agent-shell--context-usage-indicator :filter-return
              #'warashi-agent-shell--append-cost-indicator))

(provide 'warashi-agent-shell)
;;; warashi-agent-shell.el ends here

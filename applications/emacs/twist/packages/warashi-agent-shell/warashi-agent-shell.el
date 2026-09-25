;;; warashi-agent-shell.el --- agent-shell の起動と表示まわり  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (agent-shell "0.77.2") (warashi-chelly-workspace "0.1.0"))
;; Keywords: convenience, tools

;;; Commentary:

;; agent-shell に足している四つのこと。
;;
;; - model と effort を固定した起動コマンド。pi-acp 経由の pi と
;;   Copilot CLI の二系統がある。Copilot は初期化中に ACP で model、
;;   effort を順に設定し、応答を待ってから prompt を送る。
;;   起動は `agent-shell--dwim' ではなく `agent-shell--start' に session strategy
;;   new を渡して行う。起動を投げた後に picker や window の切り替えで割り込ませないため。
;;   Copilot は `warashi-chelly-workspace-root' 以下では同じ variant
;;   の設定を chelly-agent に渡す。専用 runner 非対応の pi は同領域で起動を
;;   拒否する。
;; - `project-switch-project' のディスパッチから variant を選んで起動する。
;;   起動しても shell には飛ばず、同じ project のメニューを開き直す。
;; - session の累積コストを context usage indicator の隣に常設する。実行中は
;;   確定前と分かるよう ~ を付ける。
;;
;; 利用側で `warashi-agent-shell-install-cost-indicator' を agent-shell の
;; ロード後に呼ぶ。起動コマンドは `warashi-agent-shell-define-pi-variants'、
;; `warashi-agent-shell-define-copilot-variants' で作る。

;;; Code:

(require 'map)
(require 'project)
(require 'seq)
(require 'subr-x)
;; agent-shell を実行時に require しないのは、起動コマンドを呼ぶまで agent-shell
;; を読む必要が無いため。compile 時だけ読ませる。
(eval-when-compile (require 'agent-shell))
(declare-function warashi-agent-shell-chelly--route-config
                  "warashi-agent-shell-chelly"
                  (agent provider-config directory))

;;;; 起動コマンド

(defvar warashi-agent-shell-variants nil
  "起動コマンドの一覧。要素は (NAME . COMMAND) で、定義順に並ぶ。")

(defun warashi-agent-shell-register-variant (name command)
  "NAME で選べる起動コマンド COMMAND を一覧に載せる。"
  ;; 同じ NAME を上書きするのは、init.org を評価し直すたびに候補が伸びるのを
  ;; 防ぐため。
  (if-let* ((found (assoc name warashi-agent-shell-variants)))
      (setcdr found command)
    (setq warashi-agent-shell-variants
          (append warashi-agent-shell-variants (list (cons name command))))))

(defun warashi-agent-shell--start-shell (config)
  "CONFIG で agent-shell を起動する。表示も focus もしない。"
  ;; `agent-shell--dwim' を使わないのは、起動を投げた後に割り込むため。
  ;; `agent-shell-session-strategy' が既定の prompt だと、session 確立まで待って
  ;; から picker が minibuffer を奪い、その間に始めていた別の作業を潰す。dwim は
  ;; 加えて起動元 buffer の context (eshell なら打った行そのもの) を差し込み、
  ;; window も切り替える。起動したことは shell 一覧で気付けるので、ここでは何も
  ;; 奪わない。
  (agent-shell--start :config config
                      :new-session t
                      :session-strategy 'new
                      :no-focus t))

(defun warashi-agent-shell--start-pi (model-id)
  "MODEL-ID を指定して pi agent-shell を起動する。"
  (require 'agent-shell-pi)
  (require 'warashi-agent-shell-chelly)
  (let ((config (agent-shell-pi-make-agent-config)))
    ;; :default-model-id は session 確立後に funcall されるので、動的束縛では
    ;; なく MODEL-ID を lexical に閉じ込めた関数へ差し替える。
    (setcdr (assq :default-model-id config) (lambda () model-id))
    (warashi-agent-shell--start-shell
     (warashi-agent-shell-chelly--route-config
      'pi config default-directory))))

(defmacro warashi-agent-shell-define-pi-variants (&rest variants)
  "VARIANTS から pi agent-shell の起動コマンドを定義する。
VARIANTS の各要素は (NAME MODEL-ID)。NAME ごとに
`warashi-agent-shell-pi-NAME' と、eshell から短い名前で呼ぶための
`eshell/pi-NAME' を生成する。"
  ;; thought level を取らないのは、ローカルモデルが reasoning 非対応で
  ;; 送るべき effort が無いため。
  `(progn
     ,@(mapcan
        (pcase-lambda (`(,name ,model-id))
          (let ((fn (intern (format "warashi-agent-shell-pi-%s" name)))
                (eshell-fn (intern (format "eshell/pi-%s" name))))
            (list
             `(defun ,fn ()
                ,(format "pi agent-shell を model %s で起動する。" model-id)
                (interactive)
                (warashi-agent-shell--start-pi ,model-id))
             `(defun ,eshell-fn (&rest _args)
                ,(format "eshell から `%s' を起動する。" fn)
                (,fn))
             `(warashi-agent-shell-register-variant
               ,(format "pi-%s" name) ',fn))))
        variants)))

(defun warashi-agent-shell--start-copilot (model-id thought-level)
  "MODEL-ID と THOUGHT-LEVEL を指定して Copilot agent-shell を起動する。"
  (require 'agent-shell-github)
  (require 'warashi-agent-shell-chelly)
  (let ((config (agent-shell-github-make-copilot-config)))
    ;; CLI の --model は ACP の初期表示だけに反映され、初回送信時の実モデルと
    ;; 異なり得る。init-finished の hook では prompt と競合するため、
    ;; 初期化の設定待ちに載せ、model を切り替えてから effort を適用する。
    (setcdr (assq :default-model-id config) (lambda () model-id))
    (setcdr (assq :default-config-options config)
            (lambda () (list (cons "reasoning_effort" thought-level))))
    (warashi-agent-shell--start-shell
     (warashi-agent-shell-chelly--route-config
      'copilot config default-directory))))

(defmacro warashi-agent-shell-define-copilot-variants (&rest variants)
  "VARIANTS から Copilot agent-shell の起動コマンドを定義する。
VARIANTS の各要素は (NAME MODEL-ID THOUGHT-LEVEL)。NAME ごとに
`warashi-agent-shell-copilot-NAME' と、eshell から短い名前で呼ぶための
`eshell/copilot-NAME' を生成する。"
  `(progn
     ,@(mapcan
        (pcase-lambda (`(,name ,model-id ,thought-level))
          (let ((fn (intern (format "warashi-agent-shell-copilot-%s" name)))
                (eshell-fn (intern (format "eshell/copilot-%s" name))))
            (list
             `(defun ,fn ()
                ,(format "Copilot agent-shell を model %s / effort %s で起動する。"
                         model-id thought-level)
                (interactive)
                (warashi-agent-shell--start-copilot ,model-id ,thought-level))
             `(defun ,eshell-fn (&rest _args)
                ,(format "eshell から `%s' を起動する。" fn)
                (,fn))
             `(warashi-agent-shell-register-variant
               ,(format "copilot-%s" name) ',fn))))
        variants)))

;;;; project-switch からの起動

(defun warashi-agent-shell--read-variant ()
  "起動する variant のコマンドを選ばせて返す。"
  (let ((name (completing-read "Agent shell: "
                               (mapcar #'car warashi-agent-shell-variants)
                               nil t)))
    (alist-get name warashi-agent-shell-variants nil nil #'equal)))

(defun warashi-agent-shell-project-switch ()
  "variant を選んで起動し、`project-switch-project' のメニューに戻る。"
  (interactive)
  (when-let* ((command (warashi-agent-shell--read-variant)))
    (funcall command))
  ;; メニューを開き直すのは、`project-current-directory-override' が
  ;; ディスパッチしたコマンドの終了で消えるため。起動して戻るだけでは元の
  ;; project に居る状態になり、続けて magit を開くのに project を選び直す
  ;; ことになる。project.el のメニューは 1 打鍵で閉じる読み取りループなので、
  ;; 開いたままにする手は無い。
  ;; M-x から呼んだときに開かないのは、戻る先のメニューが無いため。
  (when project-current-directory-override
    (project-switch-project project-current-directory-override)))

;;;; コスト表示

(defun warashi-agent-shell--cost-indicator ()
  "session の累積コストを表示用の文字列で返す。"
  ;; state を読むのに内部関数を使うのは、usage を取得する公開 API が無いため。
  (when-let* ((usage (map-elt (agent-shell--state) :usage))
              (amount (map-elt usage :cost-amount))
              ((> amount 0)))
    (let ((currency (map-elt usage :cost-currency))
          ;; `shell-maker-busy' は shell 以外の buffer で error を投げる。
          ;; header の描画は shell buffer 内で走るので通常は来ないが、印が
          ;; 付かないより indicator ごと消える方が困るため握り潰す。
          (busy (ignore-errors (shell-maker-busy))))
      ;; USD を $ に畳むのは、幅の限られる header で 2 文字を惜しむため。
      ;; 実行中に ~ を付けるのは、cost が claude-agent-acp の result にしか
      ;; 載らず、隣の context だけが動くあいだ前ターンの値が残るため。金額を
      ;; トークン数から自前で推定しないのは、単価表を持っても課金側のロジック
      ;; と乖離した数字を常時出すことになるため。
      (format "%s%s%.2f"
              (if busy "~" "")
              (if (member currency '(nil "USD")) "$" currency)
              amount))))

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

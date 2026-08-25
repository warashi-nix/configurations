;;; warashi-agent-shell.el --- agent-shell の起動と表示まわり  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (agent-shell "0.1.0"))
;; Keywords: convenience, tools

;;; Commentary:

;; agent-shell に足している四つのこと。
;;
;; - 単キーコマンドに入力メソッドを奪わせない。`agent-shell-mode-map' は n p r
;;   + - 0 を素のキーで握っており、プロンプト上ではそれぞれのコマンドが
;;   `self-insert-command' を直接呼ぶ。直接呼び出しは `nskk-mode-map' の
;;   `<remap> <self-insert-command>' を通らないので、konnkai が こnnかい になる。
;; - model と effort を固定した起動コマンド。effort は agent config に設定点が
;;   無く、session 確立後に ACP の config option として送るしかない。
;; - session の累積コストを context usage indicator の隣に常設する。
;; - buffer 名の project 部分を repository 名と git-wit の memo にする。
;;   worktree のディレクトリ名は ID 由来で、並べたときにどの作業か読み取れない。
;;
;; 利用側で `warashi-agent-shell-install-self-insert-advice'、
;; `warashi-agent-shell-install-cost-indicator'、
;; `warashi-agent-shell-install-git-wit-memo-name' を agent-shell のロード後に呼び、
;; `warashi-agent-shell--apply-thought-level' を `agent-shell-mode-hook' に登録
;; する。起動コマンドは `warashi-agent-shell-define-claude-variants' で作る。

;;; Code:

(require 'map)
(require 'seq)
(require 'subr-x)
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

;;;; git-wit の memo を buffer 名に出す

(defvar warashi-agent-shell-git-wit-program "git-wit"
  "git-wit の実行ファイル名かパス。")

(defvar warashi-agent-shell--shell-name-cache (make-hash-table :test #'equal)
  "ディレクトリごとに解決済みの project 名。値が nil なら差し替え無し。")

(defun warashi-agent-shell--git-wit-list (directory)
  "DIRECTORY で git-wit の worktree 一覧を引き、JSON 文字列で返す。"
  ;; call-process ではなく process-file なのは、DIRECTORY がリモートのときに
  ;; 手元の git-wit を叩くと、無関係な worktree 一覧と突き合わせて別の作業の
  ;; memo を付けてしまうため。
  (with-temp-buffer
    (let* ((default-directory directory)
           (status (ignore-errors
                     (process-file warashi-agent-shell-git-wit-program
                                   nil t nil "ls" "--json"))))
      (when (eql status 0)
        (buffer-string)))))

(defun warashi-agent-shell--git-wit-memo-in (json directory)
  "JSON に載った worktree のうち、DIRECTORY のものの memo を返す。
JSON は `warashi-agent-shell--git-wit-list' の戻り値。DIRECTORY は
リモート接頭辞を落としたパス。"
  (when-let* (((stringp json))
              (worktrees (ignore-errors
                           (json-parse-string json
                                              :object-type 'alist
                                              :null-object nil
                                              :false-object nil)))
              ;; 配列以外は git-wit の出力として扱わない。alist を舐めると
              ;; 要素が cons になり `alist-get' が型エラーになる。
              ((vectorp worktrees))
              (target (file-name-as-directory directory))
              (found (seq-find
                      (lambda (worktree)
                        (when-let* ((path (alist-get 'path worktree)))
                          (equal target (file-name-as-directory path))))
                      worktrees))
              (memo (alist-get 'memo found))
              ((not (string-empty-p memo))))
    memo))

(defun warashi-agent-shell--repository-name-in (git-common-dir)
  "GIT-COMMON-DIR から repository 名を返す。
GIT-COMMON-DIR は git rev-parse --git-common-dir の出力。"
  (when-let* (((stringp git-common-dir))
              ((not (string-empty-p git-common-dir)))
              (directory (directory-file-name git-common-dir))
              (name (file-name-nondirectory directory))
              ((not (string-empty-p name))))
    ;; worktree から見た common dir は main の .git を指すので、親が repo 名に
    ;; なる。bare repo では common dir 自体が repo なので、.git で終わるときだけ
    ;; 親に上がる。
    (if (equal name ".git")
        (warashi-agent-shell--repository-name-in
         (file-name-directory directory))
      (string-remove-suffix ".git" name))))

(defun warashi-agent-shell--repository-name (directory)
  "DIRECTORY の属する repository の名前を返す。"
  ;; git-wit の worktree は ~/.local/share/git-wit/worktrees/<id> に置かれ、
  ;; ls --json も repository を持たないので、名前は git から取るしかない。
  (with-temp-buffer
    (let* ((default-directory directory)
           (status (ignore-errors
                     (process-file "git" nil t nil "rev-parse"
                                   "--path-format=absolute" "--git-common-dir"))))
      (when (eql status 0)
        (warashi-agent-shell--repository-name-in
         (string-trim (buffer-string)))))))

(defun warashi-agent-shell--worktree-directory ()
  "memo を引く対象のディレクトリを返す。"
  ;; リモートで `file-truename' を呼ぶと接続が起きるので、symlink の解決は
  ;; ローカルのときだけにする。
  (when default-directory
    (if (file-remote-p default-directory)
        (expand-file-name default-directory)
      (ignore-errors (file-truename default-directory)))))

(defun warashi-agent-shell--resolve-shell-name (directory)
  "DIRECTORY の worktree に付いた memo から project 名を作る。"
  (when-let* ((memo (warashi-agent-shell--git-wit-memo-in
                     (warashi-agent-shell--git-wit-list directory)
                     (file-local-name directory))))
    (if-let* ((repository (warashi-agent-shell--repository-name directory)))
        (format "%s / %s" repository memo)
      memo)))

(defun warashi-agent-shell--shell-name ()
  "`default-directory' の worktree から差し替える project 名を返す。"
  (when-let* ((directory (warashi-agent-shell--worktree-directory)))
    (let ((cached (gethash directory warashi-agent-shell--shell-name-cache
                           'missing)))
      ;; 引き直さないのは、header が再描画のたびに project 名を引くため。
      ;; memo を書き換えたときに追随しないのは、この常時呼ばれる経路で
      ;; process を起こす頻度と釣り合わないため。
      (if (not (eq cached 'missing))
          cached
        (puthash directory
                 (warashi-agent-shell--resolve-shell-name directory)
                 warashi-agent-shell--shell-name-cache)))))

(defun warashi-agent-shell--project-name-with-memo (name)
  "project 名 NAME を git-wit の memo で置き換える。"
  (or (warashi-agent-shell--shell-name) name))

(defun warashi-agent-shell-install-git-wit-memo-name ()
  "buffer 名の project 部分を repository と git-wit の memo にする。"
  ;; `agent-shell-buffer-name-format' に関数を渡さないのは、そうすると
  ;; `agent-shell--buffer-name-prefix' が nil を返す仕様で、prefix を剥がして
  ;; 表示する `agent-shell-switch-buffer' と `warashi-agent-shell-list' が
  ;; どちらも劣化するため。project 名だけ差し替えれば分解可能性が残る。
  (advice-add 'agent-shell--project-name :filter-return
              #'warashi-agent-shell--project-name-with-memo))

(provide 'warashi-agent-shell)
;;; warashi-agent-shell.el ends here

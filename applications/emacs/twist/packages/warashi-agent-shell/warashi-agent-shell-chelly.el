;;; warashi-agent-shell-chelly.el --- 専用ユーザーの ACP 検証入口 -*- lexical-binding: t; -*-

;;; Commentary:

;; 通常の agent-shell の設定を変えず、chelly-agent で新規会話・再開を確認する。
;; ホストの認証設定や MCP 設定は渡さず、ホストへの操作要求も拒否する。

;;; Code:

(require 'agent-shell)
(require 'acp)
(require 'map)

(defconst warashi-agent-shell-chelly--workspace-root "/srv/chelly-workspaces/"
  "専用ユーザーの作業領域。NixOS の chelly-agent runner と対になる。")

(defun warashi-agent-shell-chelly--directory (directory)
  "DIRECTORY がローカルの専用作業領域なら実体の絶対パスを返す。"
  (when (file-remote-p directory)
    (user-error "chelly-agent ACP must be started from the workbench host, not TRAMP"))
  (let ((directory (file-name-as-directory (file-truename directory)))
        (root (file-name-as-directory
               (file-truename warashi-agent-shell-chelly--workspace-root))))
    (unless (and (file-directory-p directory)
                 (or (equal directory root)
                     (file-in-directory-p directory root)))
      (user-error "chelly-agent ACP must start inside %s" root))
    directory))

(defun warashi-agent-shell-chelly--on-request (original &rest args)
  "専用 STATE の要求だけ制限し、それ以外は ORIGINAL に ARGS を渡す。"
  (let* ((state (plist-get args :state))
         (request (plist-get args :acp-request))
         (method (map-elt request 'method)))
    (if (and (map-nested-elt state '(:agent-config :chelly-agent))
             (not (equal method "session/request_permission")))
        (progn
          (message "chelly-agent ACP: rejected host request %s" method)
          (acp-send-response
           :client (map-elt state :client)
           :response `((:request-id . ,(map-elt request 'id))
                       (:error . ,(acp-make-error
                                   :code -32601
                                   :message "Host operations are disabled for chelly-agent")))))
      (apply original args))))

;; 能力の通知は認可境界ではなく、上流の dispatcher は fs 要求を常に扱う。
(advice-add 'agent-shell--on-request :around #'warashi-agent-shell-chelly--on-request)

(defun warashi-agent-shell-chelly--start (original &rest args)
  "専用 config の初回起動・再起動を保護して ORIGINAL に ARGS を渡す。"
  (if-let* ((directory (alist-get :chelly-agent (plist-get args :config))))
      (let* ((directory (warashi-agent-shell-chelly--directory directory))
             (default-directory directory)
             (agent-shell-cwd-function (lambda () directory))
             (enable-local-variables nil)
             (enable-local-eval nil))
        (apply original args))
    (apply original args)))

;; restart/reload は公開入口を通らず、client-maker より前に dir-local を読む。
(advice-add 'agent-shell--start :around #'warashi-agent-shell-chelly--start)

(defun warashi-agent-shell-chelly--config (agent directory)
  "AGENT を専用 DIRECTORY で起動する config を作る。"
  (let* ((directory (warashi-agent-shell-chelly--directory directory))
         (config (pcase agent
                   ('claude
                    (require 'agent-shell-anthropic)
                    (agent-shell-anthropic-make-claude-code-config))
                   ('copilot
                    (require 'agent-shell-github)
                    (agent-shell-github-make-copilot-config))
                   (_ (user-error "Unsupported chelly-agent ACP agent: %s" agent))))
         (command (if (eq agent 'claude)
                      '("run" "--" "claude-agent-acp")
                    '("run" "--" "copilot" "--acp"))))
    (setf (alist-get :chelly-agent config) directory)
    (dolist (key '(:buffer-name :mode-line-name))
      (setf (alist-get key config) (concat (alist-get key config) " [chelly-agent]")))
    (setf (alist-get :client-maker config)
          (lambda (buffer)
            (with-current-buffer buffer
              (setq-local default-directory
                          (warashi-agent-shell-chelly--directory directory))
              (setq-local agent-shell-cwd-function (lambda () directory))
              (setq-local agent-shell-command-prefix nil)
              (setq-local agent-shell-text-file-capabilities nil)
              (setq-local agent-shell-mcp-servers nil)
              (setq-local agent-shell-permission-responder-function nil)
              (setq-local agent-shell-context-sources nil)
              (setq-local agent-shell-file-completion-enabled nil)
              (setq-local agent-shell-transcript-file-path-function nil)
              (setq-local enable-local-variables nil)
              (setq-local enable-local-eval nil)
              ;; provider の client-maker は本人の token getter を呼び得る。
              ;; 認証は専用 runner の envfile に任せ、ホスト側では生成しない。
              (acp-make-client :command "chelly-agent"
                              :command-params command
                              :context-buffer buffer))))
    config))

;;;###autoload
(defun warashi-agent-shell-chelly-start (agent &optional resume)
  "専用環境で AGENT の会話を開始する。RESUME が非 nil なら会話を選んで再開。
ホストの /srv/chelly-workspaces 以下から実行する。対話時は C-u で再開する。"
  (interactive (list (intern (completing-read "Dedicated ACP agent: "
                                            '("claude" "copilot") nil t))
                     current-prefix-arg))
  (unless (eq system-type 'gnu/linux)
    (user-error "chelly-agent ACP is only available on the workbench Linux host"))
  (let* ((directory (warashi-agent-shell-chelly--directory default-directory))
         (config (warashi-agent-shell-chelly--config agent directory)))
    (unless (executable-find "chelly-agent")
      (user-error "chelly-agent is not installed on this host"))
    (agent-shell--start :config config
                        :new-session t
                        :session-strategy (if resume 'prompt 'new))))

(provide 'warashi-agent-shell-chelly)
;;; warashi-agent-shell-chelly.el ends here

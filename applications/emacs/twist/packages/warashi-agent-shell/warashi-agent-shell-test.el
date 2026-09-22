;;; warashi-agent-shell-test.el --- 起動と表示まわりのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-agent-shell-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'agent-shell)
(require 'agent-shell-github)
(require 'warashi-agent-shell)
(require 'warashi-agent-shell-chelly)

(ert-deftest warashi-agent-shell-test-chelly-start-guard-keeps-normal-dir-locals ()
  "実際の dir-local 設定は専用起動だけ無効にし、通常起動では維持する。"
  (let* ((root (make-temp-file "chelly-workspace-" t))
         (warashi-chelly-workspace-root root)
         (enable-local-variables t))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name ".dir-locals.el" root)
            (insert "((nil . ((fill-column . 33))))"))
          (dolist (dedicated '(nil t))
            (with-temp-buffer
              (setq-local default-directory (file-name-as-directory root))
              (setq-local fill-column 70)
              (warashi-agent-shell-chelly--start
               (lambda (&rest _) (hack-dir-local-variables-non-file-buffer))
               :config (when dedicated
                         (warashi-agent-shell-chelly--config 'claude root)))
              (should (= (if dedicated 70 33) fill-column)))))
      (delete-directory root t))))

(ert-deftest warashi-agent-shell-test-chelly-restart-disables-dir-locals-before-client ()
  "上流の restart/reload でも新しい buffer の dir-local 適用前から無効にする。"
  (let* ((root (make-temp-file "chelly-workspace-" t))
         (warashi-chelly-workspace-root root)
         (enable-local-variables t)
         (enable-local-eval t))
    (unwind-protect
        (dolist (restart '(agent-shell-restart agent-shell-reload))
          (let ((old (generate-new-buffer " *chelly-old*"))
                (new (generate-new-buffer " *chelly-new*")))
            (unwind-protect
                (with-current-buffer old
                  (setq-local major-mode 'agent-shell-mode)
                  (setq-local default-directory (file-name-as-directory root))
                  (setq-local agent-shell--state
                              (agent-shell--make-state
                               :buffer old
                               :agent-config (warashi-agent-shell-chelly--config 'claude root)))
                  (map-put! agent-shell--state :session '((:id . "dedicated-session")))
                  (setq-local enable-local-variables nil)
                  (setq-local enable-local-eval nil)
                  (let ((observed
                         (catch 'dir-locals
                           (cl-letf (((symbol-function 'shell-maker-start-v2)
                                      (lambda (&rest _)
                                        (with-current-buffer new
                                          (setq-local default-directory root))
                                        new))
                                     ((symbol-function 'hack-dir-local-variables-non-file-buffer)
                                      (lambda ()
                                        (throw 'dir-locals
                                               (list enable-local-variables enable-local-eval)))))
                             (funcall restart)))))
                    (should (equal '(nil nil) observed))))
              (when (buffer-live-p old) (kill-buffer old))
              (when (buffer-live-p new) (kill-buffer new)))))
      (delete-directory root t))))

(ert-deftest warashi-agent-shell-test-chelly-rejects-host-requests ()
  "専用セッションは能力を無視した要求も拒否し、ホストの処理へ渡さない。"
  (dolist (method '("fs/read_text_file" "fs/write_text_file" "terminal/create"
                    "session/push" "future/operation"))
    (let ((state '((:agent-config . ((:chelly-agent . t))) (:client . client)))
          response)
      (cl-letf (((symbol-function 'acp-send-response)
                 (lambda (&rest args) (setq response (plist-get args :response)))))
        (warashi-agent-shell-chelly--on-request
         (lambda (&rest _) (ert-fail "Host request handler was called"))
         :state state :acp-request `((id . 42) (method . ,method)))
        (should (equal 42 (alist-get :request-id response)))
        (should (equal -32601 (map-nested-elt response '(:error code))))))))

(ert-deftest warashi-agent-shell-test-chelly-keeps-permission-ui-and-normal-clients ()
  "専用の権限確認 UI と通常セッションの要求は既存の処理を使う。"
  (dolist (case '((t "session/request_permission") (nil "fs/read_text_file")))
    (let* ((args (list :state `((:agent-config . ((:chelly-agent . ,(car case)))))
                       :acp-request `((method . ,(cadr case)))))
           captured)
      (apply #'warashi-agent-shell-chelly--on-request
             (lambda (&rest received) (setq captured received)) args)
      (should (equal args captured)))))

(ert-deftest warashi-agent-shell-test-chelly-directory-boundary ()
  "TRAMP、対象外のパス、対象外へ向く symlink は入口で拒否する。"
  (let* ((root (make-temp-file "chelly-workspace-" t))
         (outside (make-temp-file "chelly-outside-" t))
         (warashi-chelly-workspace-root (file-name-as-directory root)))
    (unwind-protect
        (progn
          (should (equal (file-name-as-directory (file-truename root))
                         (warashi-agent-shell-chelly--directory root)))
          (should-error (warashi-agent-shell-chelly--directory outside) :type 'user-error)
          (should-error (warashi-agent-shell-chelly--directory "/ssh:workbench:/srv/chelly-workspaces/")
                        :type 'user-error)
          (make-symbolic-link outside (expand-file-name "escape" root))
          (should-error (warashi-agent-shell-chelly--directory (expand-file-name "escape" root))
                        :type 'user-error))
      (delete-directory root t)
      (delete-directory outside t))))

(ert-deftest warashi-agent-shell-test-chelly-client-keeps-isolation-on-recreation ()
  "client 再生成でも専用入口と buffer-local な制限を保持し、個人の設定を渡さない。"
  (let* ((root (make-temp-file "chelly-workspace-" t))
         (warashi-chelly-workspace-root (file-name-as-directory root))
         (agent-shell-command-prefix '("personal-launcher"))
         (agent-shell-text-file-capabilities t)
         (agent-shell-mcp-servers '(((name . "personal")))))
    (unwind-protect
        (dolist (agent '(claude copilot))
          (let* ((config (warashi-agent-shell-chelly--config agent root))
                 (make-client (alist-get :client-maker config)))
            (dotimes (_ 2)
              (with-temp-buffer
                (let ((client (funcall make-client (current-buffer))))
                  (should (equal "chelly-agent" (map-elt client :command)))
                  (should (equal (if (eq agent 'claude)
                                     '("run" "--" "claude-agent-acp")
                                   '("run" "--" "copilot" "--acp"))
                                 (map-elt client :command-params)))
                  (should-not (map-elt client :environment-variables))
                  (should-not agent-shell-text-file-capabilities)
                  (should-not agent-shell-mcp-servers)
                  (should-not agent-shell-permission-responder-function)
                  (should-not agent-shell-transcript-file-path-function)
                  (should-not enable-local-variables)
                  (should-not enable-local-eval)
                  (should (equal (file-name-as-directory (file-truename root))
                                 (agent-shell-cwd))))))))
      (delete-directory root t))
    (should agent-shell-text-file-capabilities)
    (should agent-shell-mcp-servers)
    (should (equal '("personal-launcher") agent-shell-command-prefix))))

(ert-deftest warashi-agent-shell-test-chelly-start-and-resume ()
  "専用入口は新規 buffer で起動し、再開時だけ既存 session の選択を行う。"
  (skip-unless (eq system-type 'gnu/linux))
  (let* ((root (make-temp-file "chelly-workspace-" t))
         (warashi-chelly-workspace-root (file-name-as-directory root))
         (default-directory root)
         (agent-shell-command-prefix '("personal-launcher")))
    (unwind-protect
        (dolist (resume '(nil t))
          (let (captured)
            (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/test/chelly-agent"))
                      ((symbol-function 'agent-shell--start)
                       (lambda (&rest args)
                         (setq captured args))))
              (warashi-agent-shell-chelly-start 'claude resume)
              (should (plist-get captured :new-session))
              (should (eq (if resume 'prompt 'new) (plist-get captured :session-strategy)))
              (should (alist-get :chelly-agent (plist-get captured :config))))))
      (delete-directory root t))))

(defmacro warashi-agent-shell-test--capture-start (&rest body)
  "BODY 中の `agent-shell--start' の引数を返す。"
  (declare (indent 0))
  `(let ((captured nil))
     (cl-letf (((symbol-function 'agent-shell-anthropic-make-claude-code-config)
                (lambda (&rest _) (list (cons :default-model-id #'ignore))))
               ((symbol-function 'agent-shell-pi-make-agent-config)
                (lambda (&rest _) (list (cons :default-model-id #'ignore))))
               ((symbol-function 'agent-shell--start)
                (lambda (&rest args) (setq captured args))))
       ,@body)
     captured))

(ert-deftest warashi-agent-shell-test-ordinary-variants-route-inside-chelly-workspace ()
  "通常の Claude/Copilot variant も専用領域では設定を保ったまま専用 runner を使う。"
  (skip-unless (eq system-type 'gnu/linux))
  (let* ((root (make-temp-file "chelly-workspace-" t))
         (clone (expand-file-name "owner/repository/clone" root))
         (alias-parent (make-temp-file "chelly-alias-" t))
         (alias (expand-file-name "workspace" alias-parent))
         (warashi-chelly-workspace-root (file-name-as-directory root)))
    (unwind-protect
        (progn
          (make-directory clone t)
          (make-symbolic-link root alias)
          (dolist (directory (list root clone
                                   (expand-file-name "owner/repository/clone"
                                                     alias)))
            (let ((default-directory (file-name-as-directory directory)))
              (dolist (case '((claude "opus[1m]" "low")
                              (copilot "gpt-6-astra" "medium")))
                (let* ((agent (nth 0 case))
                       (model (nth 1 case))
                       (effort (nth 2 case))
                       (captured
                        (warashi-agent-shell-test--capture-start
                          (if (eq agent 'claude)
                              (warashi-agent-shell--start-claude model effort)
                            (warashi-agent-shell--start-copilot model effort))))
                       (config (plist-get captured :config))
                       (client (with-temp-buffer
                                 (funcall (alist-get :client-maker config)
                                          (current-buffer)))))
                  (should (plist-get captured :no-focus))
                  (should (eq 'new (plist-get captured :session-strategy)))
                  (should (alist-get :chelly-agent config))
                  (should (equal model
                                 (funcall (alist-get :default-model-id config))))
                  (if (eq agent 'claude)
                      (should (equal effort
                                     (alist-get :warashi-thought-level config)))
                    (should
                     (equal `(("reasoning_effort" . ,effort))
                            (funcall
                             (alist-get :default-config-options config)))))
                  (should (equal "chelly-agent" (map-elt client :command))))))))
      (delete-directory alias-parent t)
      (delete-directory root t))))

(ert-deftest warashi-agent-shell-test-ordinary-variants-refuse-chelly-symlink-escape ()
  "専用領域に見えて実体が外なら個人 credential へ fallback しない。"
  (let* ((root (make-temp-file "chelly-workspace-" t))
         (outside (make-temp-file "chelly-outside-" t))
         (escape (expand-file-name "escape" root))
         (warashi-chelly-workspace-root (file-name-as-directory root)))
    (unwind-protect
        (progn
          (make-symbolic-link outside escape)
          (let ((default-directory (file-name-as-directory escape)))
            (should-error
             (warashi-agent-shell-test--capture-start
               (warashi-agent-shell--start-claude "opus[1m]" "low"))
             :type 'user-error)
            (should-error
             (warashi-agent-shell-test--capture-start
               (warashi-agent-shell--start-copilot "gpt-6-astra" "medium"))
             :type 'user-error)))
      (delete-directory root t)
      (delete-directory outside t))))

(ert-deftest warashi-agent-shell-test-dedicated-routing-is-linux-only ()
  "専用領域は Linux 以外で個人 provider へ fallback しない。"
  (let* ((root (make-temp-file "chelly-workspace-" t))
         (warashi-chelly-workspace-root root)
         (default-directory (file-name-as-directory root))
         (system-type 'darwin))
    (unwind-protect
        (should-error
         (warashi-agent-shell-test--capture-start
           (warashi-agent-shell--start-claude "opus[1m]" "low"))
         :type 'user-error)
      (delete-directory root t))))

(ert-deftest warashi-agent-shell-test-pi-refuses-dedicated-workspace ()
  "専用 runner 非対応の Pi は個人 credential で起動しない。"
  (let* ((root (make-temp-file "chelly-workspace-" t))
         (warashi-chelly-workspace-root root)
         (default-directory (file-name-as-directory root)))
    (unwind-protect
        (should-error
         (warashi-agent-shell-test--capture-start
           (warashi-agent-shell--start-pi "athena/ornith-1-5-9b"))
         :type 'user-error)
      (delete-directory root t))))

(defvar warashi-agent-shell-test--state nil
  "テスト用の `agent-shell--state' の戻り値。")

(defmacro warashi-agent-shell-test--with-state (state &rest body)
  "`agent-shell--state' が STATE を返す状況で BODY を実行する。"
  (declare (indent 1))
  `(let ((warashi-agent-shell-test--state ,state))
     (cl-letf (((symbol-function 'agent-shell--state)
                (lambda (&rest _) warashi-agent-shell-test--state)))
       ,@body)))

;;;; thought level

(ert-deftest warashi-agent-shell-test-thought-level-subscribes ()
  "config に thought level があれば init-finished で送る。"
  (let ((subscription nil)
        (sent nil))
    (cl-letf (((symbol-function 'agent-shell-subscribe-to)
               (lambda (&rest args) (setq subscription args)))
              ((symbol-function 'agent-shell--config-option-set-thought-level-id)
               (lambda (&rest args) (setq sent (plist-get args :thought-level-id)))))
      (warashi-agent-shell-test--with-state
          '((:agent-config . ((:warashi-thought-level . "xhigh"))))
        (warashi-agent-shell--apply-thought-level))
      (should (eq 'init-finished (plist-get subscription :event)))
      (should (eq (current-buffer) (plist-get subscription :shell-buffer)))
      ;; session 確立前には送らない。確立後のイベントで初めて送る。
      (should-not sent)
      (funcall (plist-get subscription :on-event) nil)
      (should (equal "xhigh" sent)))))

(ert-deftest warashi-agent-shell-test-thought-level-absent ()
  "thought level を持たない config では何もしない。"
  (let ((subscribed nil))
    (cl-letf (((symbol-function 'agent-shell-subscribe-to)
               (lambda (&rest _) (setq subscribed t))))
      (warashi-agent-shell-test--with-state '((:agent-config . nil))
        (warashi-agent-shell--apply-thought-level))
      (warashi-agent-shell-test--with-state nil
        (warashi-agent-shell--apply-thought-level))
      (should-not subscribed))))

;;;; 起動コマンド

(ert-deftest warashi-agent-shell-test-start-claude-config ()
  "model と thought level が config に載り、新規 session を割り込み無しで起動する。"
  (let* ((captured (warashi-agent-shell-test--capture-start
                     (warashi-agent-shell--start-claude "opus[1m]" "low")))
         (config (plist-get captured :config)))
    (should (plist-get captured :new-session))
    ;; session strategy を new で上書きするのは、既定の prompt だと session
    ;; 確立後に picker が minibuffer を奪うため。
    (should (eq 'new (plist-get captured :session-strategy)))
    ;; no-focus なのは、起動を投げた後に window を取り返されないため。
    (should (plist-get captured :no-focus))
    ;; :default-model-id は session 確立後に funcall される。
    (should (equal "opus[1m]" (funcall (alist-get :default-model-id config))))
    (should (equal "low" (alist-get :warashi-thought-level config)))
    (should-not (alist-get :chelly-agent config))))

(ert-deftest warashi-agent-shell-test-start-claude-keeps-model-per-shell ()
  "先に起動した shell の model が、後の起動で書き換わらない。
:default-model-id を動的束縛ではなく lexical に閉じ込めているため。"
  (let* ((first (alist-get :default-model-id
                           (plist-get (warashi-agent-shell-test--capture-start
                                        (warashi-agent-shell--start-claude "sonnet" "xhigh"))
                                      :config))))
    (warashi-agent-shell-test--capture-start
      (warashi-agent-shell--start-claude "opus[1m]" "low"))
    (should (equal "sonnet" (funcall first)))))

(ert-deftest warashi-agent-shell-test-define-claude-variants ()
  "variant ごとにコマンドと eshell 用の関数を定義する。"
  (warashi-agent-shell-define-claude-variants
   (warashi-agent-shell-test-variant "test-model" "high"))
  (should (commandp 'warashi-agent-shell-claude-warashi-agent-shell-test-variant))
  (should (fboundp 'eshell/claude-warashi-agent-shell-test-variant))
  (let ((args nil))
    (cl-letf (((symbol-function 'warashi-agent-shell--start-claude)
               (lambda (&rest a) (setq args a))))
      (funcall 'eshell/claude-warashi-agent-shell-test-variant)
      (should (equal '("test-model" "high") args)))))

(ert-deftest warashi-agent-shell-test-start-pi-config ()
  "model が config に載り、新規 session を割り込み無しで起動する。"
  (let* ((captured (warashi-agent-shell-test--capture-start
                     (warashi-agent-shell--start-pi "athena/ornith-1-5-9b")))
         (config (plist-get captured :config)))
    (should (plist-get captured :new-session))
    ;; session strategy を new で上書きするのは、既定の prompt だと session
    ;; 確立後に picker が minibuffer を奪うため。
    (should (eq 'new (plist-get captured :session-strategy)))
    ;; no-focus なのは、起動を投げた後に window を取り返されないため。
    (should (plist-get captured :no-focus))
    ;; :default-model-id は session 確立後に funcall される。
    (should (equal "athena/ornith-1-5-9b"
                   (funcall (alist-get :default-model-id config))))))

(ert-deftest warashi-agent-shell-test-start-pi-keeps-model-per-shell ()
  "先に起動した shell の model が、後の起動で書き換わらない。"
  (let ((first (alist-get :default-model-id
                          (plist-get (warashi-agent-shell-test--capture-start
                                       (warashi-agent-shell--start-pi "athena/ornith-1-5-9b"))
                                     :config))))
    (warashi-agent-shell-test--capture-start
      (warashi-agent-shell--start-pi "athena/other"))
    (should (equal "athena/ornith-1-5-9b" (funcall first)))))

(ert-deftest warashi-agent-shell-test-define-pi-variants ()
  "variant ごとにコマンドと eshell 用の関数を定義する。"
  (warashi-agent-shell-define-pi-variants
   (warashi-agent-shell-test-variant "test/model"))
  (should (commandp 'warashi-agent-shell-pi-warashi-agent-shell-test-variant))
  (should (fboundp 'eshell/pi-warashi-agent-shell-test-variant))
  (let ((args nil))
    (cl-letf (((symbol-function 'warashi-agent-shell--start-pi)
               (lambda (&rest a) (setq args a))))
      (funcall 'eshell/pi-warashi-agent-shell-test-variant)
      (should (equal '("test/model") args)))))

(ert-deftest warashi-agent-shell-test-start-copilot-config ()
  "Copilot は ACP で model と effort を設定し、作業場所を変えず割り込み無しで起動する。"
  (let* ((default-directory "/ssh:athena:/work/project/")
         (agent-shell-github-default-model-id "other-model")
         (agent-shell-github-acp-command '("custom-copilot" "--acp" "--no-color"))
         (agent-shell-github-environment '("TEST=value"))
         (captured
          (cl-letf (((symbol-function 'file-truename)
                     (lambda (&rest _)
                       (ert-fail "TRAMP routing resolved a remote path"))))
            (warashi-agent-shell-test--capture-start
              (warashi-agent-shell--start-copilot "gpt-5.6-luna" "low"))))
         (config (plist-get captured :config))
         (client-args nil))
    (should (plist-get captured :new-session))
    (should (eq 'new (plist-get captured :session-strategy)))
    (should (plist-get captured :no-focus))
    (should (equal "gpt-5.6-luna" (funcall (alist-get :default-model-id config))))
    (should (equal '(("reasoning_effort" . "low"))
                   (funcall (alist-get :default-config-options config))))
    (should-not (alist-get :warashi-thought-level config))
    (should-not (alist-get :chelly-agent config))
    (cl-letf (((symbol-function 'agent-shell--make-acp-client)
               (lambda (&rest args)
                 (should (equal default-directory "/ssh:athena:/work/project/"))
                 (setq client-args args))))
      (funcall (alist-get :client-maker config) (current-buffer)))
    (should (equal "custom-copilot" (plist-get client-args :command)))
    (should (equal '("--acp" "--no-color")
                   (plist-get client-args :command-params)))
    (should (equal '("TEST=value") (plist-get client-args :environment-variables)))
    (should (eq (current-buffer) (plist-get client-args :context-buffer)))
    (should (equal '("custom-copilot" "--acp" "--no-color")
                   agent-shell-github-acp-command))))

(ert-deftest warashi-agent-shell-test-start-copilot-keeps-settings-per-shell ()
  "session 確立後に読む model と effort は他の shell の起動に影響されない。"
  (let* ((agent-shell-github-acp-command '("copilot" "--acp"))
         (first (plist-get (warashi-agent-shell-test--capture-start
                            (warashi-agent-shell--start-copilot "gpt-5.6-luna" "low"))
                          :config))
         (second (plist-get (warashi-agent-shell-test--capture-start
                             (warashi-agent-shell--start-copilot "gpt-6-astra" "medium"))
                           :config)))
    (cl-letf (((symbol-function 'agent-shell--make-acp-client) #'list))
      (dolist (case `((,second "gpt-6-astra" "medium")
                      (,first "gpt-5.6-luna" "low")))
        (let* ((config (car case))
               (client (funcall (alist-get :client-maker config) (current-buffer))))
          (should (equal (cadr case) (funcall (alist-get :default-model-id config))))
          (should (equal (list (cons "reasoning_effort" (caddr case)))
                         (funcall (alist-get :default-config-options config))))
          (should (equal '("--acp") (plist-get client :command-params))))))))

(ert-deftest warashi-agent-shell-test-define-copilot-variants ()
  "Copilot の variant は M-x と eshell から同じ設定で起動し、再定義で候補が増えない。"
  (let ((warashi-agent-shell-variants nil)
        (args nil))
    (dotimes (_ 2)
      (warashi-agent-shell-define-copilot-variants
       (warashi-agent-shell-test-variant "gpt-6-astra" "medium")))
    (should (commandp 'warashi-agent-shell-copilot-warashi-agent-shell-test-variant))
    (should (equal '(("copilot-warashi-agent-shell-test-variant"
                      . warashi-agent-shell-copilot-warashi-agent-shell-test-variant))
                   warashi-agent-shell-variants))
    (cl-letf (((symbol-function 'warashi-agent-shell--start-copilot)
               (lambda (&rest a) (setq args a))))
      (call-interactively 'warashi-agent-shell-copilot-warashi-agent-shell-test-variant)
      (should (equal '("gpt-6-astra" "medium") args))
      (setq args nil)
      (funcall 'eshell/copilot-warashi-agent-shell-test-variant)
      (should (equal '("gpt-6-astra" "medium") args)))))

(ert-deftest warashi-agent-shell-test-copilot-settings-before-prompts ()
  "初期表示が指定値でも ACP 設定を送り、両方の応答を待ってから初回 prompt を送る。"
  (dolist (model '("gpt-5.6-luna" "gpt-5.6-terra" "gpt-5.6-sol" "gpt-6-astra"))
    (dolist (effort '("low" "medium"))
      (let ((config (plist-get (warashi-agent-shell-test--capture-start
                                (warashi-agent-shell--start-copilot model effort))
                              :config))
            (requests nil)
            (prompts nil)
            (actual-model "auto")
            (actual-effort "high"))
        (with-temp-buffer
          (setq-local major-mode 'agent-shell-mode)
          (setq-local agent-shell--state
                      (agent-shell--make-state :agent-config config :buffer (current-buffer)))
          (map-put! agent-shell--state :client
                    '((:request-handlers . t) (:notification-handlers . t) (:error-handlers . t)))
          (map-put! agent-shell--state :initialized t)
          (map-put! (map-elt agent-shell--state :session) :id "copilot-test")
          (agent-shell--save-config-options
           :state agent-shell--state
           :acp-config-options
           `[((id . "model") (name . "Model") (category . "model")
              (type . "select") (currentValue . ,model)
              (options . [((value . ,model) (name . ,model))]))
             ((id . "reasoning_effort") (name . "Reasoning effort")
              (category . "thought_level") (type . "select") (currentValue . ,effort)
              (options . [((value . "low") (name . "Low"))
                          ((value . "medium") (name . "Medium"))]))])
          (cl-letf (((symbol-function 'shell-maker--current-request-id) (lambda () 1))
                    ((symbol-function 'agent-shell--update-bootstrapping-fragment) #'ignore)
                    ((symbol-function 'agent-shell--update-header-and-mode-line) #'ignore)
                    ((symbol-function 'agent-shell--emit-event) #'ignore)
                    ((symbol-function 'agent-shell--send-request)
                     (lambda (&rest args) (push args requests)))
                    ((symbol-function 'agent-shell--send-command)
                     (lambda (&rest args)
                       (push (list (plist-get args :prompt) actual-model actual-effort) prompts))))
            (agent-shell--handle :command "first" :shell-buffer (current-buffer))
            (should-not prompts)
            (should (= 1 (length requests)))
            (let* ((pending (pop requests))
                   (request (plist-get pending :request)))
              (should (equal "session/set_config_option" (map-elt request :method)))
              (should (equal "model" (map-nested-elt request '(:params configId))))
              (should (equal model (map-nested-elt request '(:params value))))
              (setq actual-model model)
              (funcall (plist-get pending :on-success) nil))
            (should-not prompts)
            (should (= 1 (length requests)))
            (let* ((pending (pop requests))
                   (request (plist-get pending :request)))
              (should (equal "session/set_config_option" (map-elt request :method)))
              (should (equal "reasoning_effort" (map-nested-elt request '(:params configId))))
              (should (equal effort (map-nested-elt request '(:params value))))
              (setq actual-effort effort)
              (funcall (plist-get pending :on-success) nil))
            (should (equal (list (list "first" model effort)) prompts))
            (agent-shell--handle :command "second" :shell-buffer (current-buffer))
            (should (equal (list (list "second" model effort)
                                 (list "first" model effort))
                           prompts))
            (setq actual-model "manually-selected-model"
                  actual-effort "high")
            (agent-shell--handle :command "third" :shell-buffer (current-buffer))
            (should (equal '("third" "manually-selected-model" "high") (car prompts)))
            (should-not requests)))))))

;;;; project-switch からの起動

(ert-deftest warashi-agent-shell-test-variants-registered ()
  "variant は claude / pi の別が付いた名前で定義順に一覧へ載る。"
  (let ((warashi-agent-shell-variants nil))
    (warashi-agent-shell-define-claude-variants
     (warashi-agent-shell-test-registered "test-model" "high"))
    (warashi-agent-shell-define-pi-variants
     (warashi-agent-shell-test-registered "test/model"))
    (should (equal
             '(("claude-warashi-agent-shell-test-registered"
                . warashi-agent-shell-claude-warashi-agent-shell-test-registered)
               ("pi-warashi-agent-shell-test-registered"
                . warashi-agent-shell-pi-warashi-agent-shell-test-registered))
             warashi-agent-shell-variants))))

(ert-deftest warashi-agent-shell-test-variants-not-duplicated ()
  "同じ名前で定義し直しても一覧は増えない。
init.org を評価し直すたびに候補が伸びると選べなくなるため。"
  (let ((warashi-agent-shell-variants nil))
    (warashi-agent-shell-define-claude-variants
     (warashi-agent-shell-test-redefined "test-model" "high"))
    (warashi-agent-shell-define-claude-variants
     (warashi-agent-shell-test-redefined "other-model" "low"))
    (should (equal 1 (length warashi-agent-shell-variants)))))

(ert-deftest warashi-agent-shell-test-project-switch-starts-and-reopens ()
  "選んだ variant を起動し、同じ project のディスパッチを開き直す。"
  (let ((warashi-agent-shell-variants
         '(("claude-test" . warashi-agent-shell-test--variant-command)))
        (started nil)
        (reopened nil)
        (project-current-directory-override "/tmp/warashi-agent-shell-test/"))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "claude-test"))
              ((symbol-function 'warashi-agent-shell-test--variant-command)
               (lambda () (setq started t)))
              ((symbol-function 'project-switch-project)
               (lambda (dir) (setq reopened dir))))
      (warashi-agent-shell-project-switch))
    (should started)
    ;; 起動しただけだと default-directory が元の project に戻り、続けて
    ;; magit を開くのに project を選び直すことになる。
    (should (equal "/tmp/warashi-agent-shell-test/" reopened))))

(ert-deftest warashi-agent-shell-test-project-switch-outside-dispatch ()
  "ディスパッチ外から呼んだときはメニューを開かない。"
  (let ((warashi-agent-shell-variants
         '(("claude-test" . warashi-agent-shell-test--variant-command)))
        (started nil)
        (reopened nil)
        (project-current-directory-override nil))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "claude-test"))
              ((symbol-function 'warashi-agent-shell-test--variant-command)
               (lambda () (setq started t)))
              ((symbol-function 'project-switch-project)
               (lambda (dir) (setq reopened dir))))
      (warashi-agent-shell-project-switch))
    (should started)
    (should-not reopened)))

;;;; コスト表示

(ert-deftest warashi-agent-shell-test-cost-indicator ()
  "累積コストを通貨記号付きで畳んで返す。"
  (warashi-agent-shell-test--with-state
      '((:usage . ((:cost-amount . 1.234) (:cost-currency . "USD"))))
    (should (equal "$1.23" (warashi-agent-shell--cost-indicator))))
  (warashi-agent-shell-test--with-state
      '((:usage . ((:cost-amount . 2.5))))
    (should (equal "$2.50" (warashi-agent-shell--cost-indicator))))
  ;; USD 以外は畳まずにそのまま出す。
  (warashi-agent-shell-test--with-state
      '((:usage . ((:cost-amount . 3) (:cost-currency . "EUR"))))
    (should (equal "EUR3.00" (warashi-agent-shell--cost-indicator)))))

(ert-deftest warashi-agent-shell-test-cost-indicator-empty ()
  "コストが無い、または 0 のあいだは何も出さない。"
  (warashi-agent-shell-test--with-state nil
    (should-not (warashi-agent-shell--cost-indicator)))
  (warashi-agent-shell-test--with-state '((:usage . nil))
    (should-not (warashi-agent-shell--cost-indicator)))
  (warashi-agent-shell-test--with-state '((:usage . ((:cost-amount . 0))))
    (should-not (warashi-agent-shell--cost-indicator))))

(ert-deftest warashi-agent-shell-test-cost-indicator-busy ()
  "ターン実行中は確定前の値と分かる印を付ける。"
  (cl-letf (((symbol-function 'shell-maker-busy) (lambda () t)))
    (warashi-agent-shell-test--with-state
        '((:usage . ((:cost-amount . 1.5))))
      (should (equal "~$1.50" (warashi-agent-shell--cost-indicator)))))
  (cl-letf (((symbol-function 'shell-maker-busy) (lambda () nil)))
    (warashi-agent-shell-test--with-state
        '((:usage . ((:cost-amount . 1.5))))
      (should (equal "$1.50" (warashi-agent-shell--cost-indicator)))))
  ;; shell 以外の buffer から呼ばれても印を付けずに出す。
  (cl-letf (((symbol-function 'shell-maker-busy)
             (lambda () (error "Not in a shell"))))
    (warashi-agent-shell-test--with-state
        '((:usage . ((:cost-amount . 1.5))))
      (should (equal "$1.50" (warashi-agent-shell--cost-indicator))))))

(ert-deftest warashi-agent-shell-test-append-cost-indicator ()
  "context indicator の後ろに cost を足す。"
  (warashi-agent-shell-test--with-state
      '((:usage . ((:cost-amount . 1.5))))
    (should (equal "80% $1.50" (warashi-agent-shell--append-cost-indicator "80%")))
    ;; context 未取得の段階で cost だけ返すと、header に何の値か分からない数字が
    ;; 現れる。
    (should-not (warashi-agent-shell--append-cost-indicator nil)))
  (warashi-agent-shell-test--with-state nil
    (should (equal "80%" (warashi-agent-shell--append-cost-indicator "80%")))))

(provide 'warashi-agent-shell-test)
;;; warashi-agent-shell-test.el ends here

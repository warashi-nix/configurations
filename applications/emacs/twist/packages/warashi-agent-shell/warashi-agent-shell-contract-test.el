;;; warashi-agent-shell-contract-test.el --- 上流 agent-shell との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-agent-shell が agent-shell に対して前提にしている呼び出し形を、
;; スタブを一切置かずに実物へ突き当てて検証する。
;;
;; 単体テスト (warashi-agent-shell-test.el) は agent-shell--state などを
;; cl-letf で差し替えるので、上流がそれらを改名・削除・仕様変更しても緑の
;; まま通る。epkgs の自動更新 PR で壊れたことに気付けるのがこの層。
;;
;; state の中身は agent-shell 同梱の mock agent の config を agent-shell--make-state
;; に渡して組む。session の確立は要らない。
;;
;; twist の env でのみ成立する。素の Emacs には agent-shell が無いため、
;; just test-emacs (ファイル名が <pkg>-test.el に完全一致するものだけを
;; 拾う) の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'find-func)
(require 'agent-shell)
(require 'shell-maker)
(require 'agent-shell-anthropic)
(require 'agent-shell-pi)
(require 'agent-shell-github)
(require 'agent-shell-mock-agent)
(require 'warashi-agent-shell)
(require 'warashi-agent-shell-chelly)

(ert-deftest warashi-agent-shell-contract-test-chelly-denies-through-subscription ()
  "実物の購読経路でも専用 agent の要求はホストのファイルを読み書きしない。"
  (let ((root (make-temp-file "chelly-acp-contract-" t)))
    (unwind-protect
        (with-temp-buffer
          (let* ((warashi-agent-shell-chelly--workspace-root root)
                 (config (warashi-agent-shell-chelly--config 'claude root))
                 (client (funcall (alist-get :client-maker config) (current-buffer)))
                 (state (agent-shell--make-state :agent-config config :buffer (current-buffer)))
                 (target (expand-file-name "must-not-be-created" root))
                 responses)
            (map-put! state :client client)
            (map-put! client :response-sender
                      (lambda (&rest args) (push (plist-get args :response) responses)))
            (agent-shell--subscribe-to-client-events :state state)
            (dolist (method '("fs/read_text_file" "fs/write_text_file"
                              "terminal/create" "session/push" "unknown/method"))
              (with-temp-buffer
                (dolist (handler (map-elt client :request-handlers))
                  (funcall handler `((id . 9) (method . ,method)
                                     (params . ((path . ,target) (content . "unexpected")))))))
              (should (equal -32601 (map-nested-elt (car responses) '(:error code))))
              (should-not (map-contains-key (car responses) :result))
              (should-not (file-exists-p target)))
            (should (= 5 (length responses)))))
      (delete-directory root t))))

(ert-deftest warashi-agent-shell-contract-test-chelly-capability-shape ()
  "専用 buffer の設定を ACP の initialize に渡すと fs は false、端末能力は無い。"
  (let ((root (make-temp-file "chelly-acp-contract-" t)))
    (unwind-protect
        (with-temp-buffer
          (let* ((warashi-agent-shell-chelly--workspace-root root)
                 (config (warashi-agent-shell-chelly--config 'copilot root)))
            (funcall (alist-get :client-maker config) (current-buffer))
            (let ((caps (map-nested-elt
                         (acp-make-initialize-request
                          :protocol-version 1
                          :read-text-file-capability agent-shell-text-file-capabilities
                          :write-text-file-capability agent-shell-text-file-capabilities)
                         '(:params clientCapabilities))))
              (should (eq :false (map-nested-elt caps '(fs readTextFile))))
              (should (eq :false (map-nested-elt caps '(fs writeTextFile))))
              (should-not (map-elt caps 'terminal)))))
      (delete-directory root t))))

(defun warashi-agent-shell-contract-test--keywords (fn)
  "FN の定義をソースから読み、`&key' に並ぶキーワードの一覧を返す。
バイトコンパイル後の `func-arity' や `help-function-arglist' は cl-defun の
キーワードを (&rest rest) に潰してしまい、キーワードの改名・削除を検出で
きない。実際に呼んで確かめる手もあるが、`agent-shell--start' のように呼
ぶと外部プロセスを起こす関数が対象に含まれるため採らない。"
  (let ((loc (find-function-noselect fn t)))
    (with-current-buffer (car loc)
      (goto-char (cdr loc))
      (let* ((arglist (nth 2 (read (current-buffer))))
             (tail (cdr (memq '&key arglist))))
        (mapcar (lambda (arg) (intern (format ":%s" (if (consp arg) (car arg) arg))))
                (seq-take-while (lambda (arg) (not (memq arg '(&rest &optional &aux))))
                                tail))))))

;;;; shell の起動

(ert-deftest warashi-agent-shell-contract-test-start-keywords ()
  "`agent-shell--start' が起動に使うキーワードを受ける。"
  (let ((keywords (warashi-agent-shell-contract-test--keywords 'agent-shell--start)))
    (dolist (keyword '(:config :new-session :session-strategy :no-focus))
      (should (memq keyword keywords)))))

(ert-deftest warashi-agent-shell-contract-test-agent-configs ()
  "agent config が :default-model-id を差し替えられる alist で返る。"
  (dolist (make '(agent-shell-anthropic-make-claude-code-config
                  agent-shell-pi-make-agent-config
                  agent-shell-github-make-copilot-config))
    (should (equal '(0 . 0) (func-arity make)))
    (should (assq :default-model-id (funcall make)))))

(ert-deftest warashi-agent-shell-contract-test-chelly-decorates-provider-config ()
  "実物の provider config を専用化しても model/effort の設定点を保持する。"
  (let* ((root (make-temp-file "chelly-acp-contract-" t))
         (warashi-agent-shell-chelly--workspace-root root))
    (unwind-protect
        (dolist (case
                 `((claude ,#'agent-shell-anthropic-make-claude-code-config)
                   (copilot ,#'agent-shell-github-make-copilot-config)))
          (let* ((agent (car case))
                 (config (funcall (cadr case)))
                 (model (lambda () "selected-model"))
                 (options (lambda () '(("reasoning_effort" . "medium"))))
                 decorated)
            (setf (alist-get :default-model-id config) model)
            (when (eq agent 'copilot)
              (setf (alist-get :default-config-options config) options))
            (setq decorated
                  (warashi-agent-shell-chelly--config agent root config))
            (should (eq model (alist-get :default-model-id decorated)))
            (when (eq agent 'copilot)
              (should (eq options
                          (alist-get :default-config-options decorated))))
            (should (alist-get :chelly-agent decorated))))
      (delete-directory root t))))

(ert-deftest warashi-agent-shell-contract-test-copilot-client-maker ()
  "Copilot の client-maker は buffer を受け、生成時の command 設定を参照する。"
  (let* ((config (agent-shell-github-make-copilot-config))
         (agent-shell-github-acp-command
          '("copilot" "--acp" "--model" "gpt-6-astra" "--effort" "low"))
         (client (funcall (alist-get :client-maker config) (current-buffer))))
    (should (equal "copilot" (map-elt client :command)))
    (should (equal '("--acp" "--model" "gpt-6-astra" "--effort" "low")
                   (map-elt client :command-params)))))

(ert-deftest warashi-agent-shell-contract-test-copilot-default-config-options ()
  "Copilot config が初期化中に順次適用する追加設定を保持できる。"
  (should (assq :default-config-options (agent-shell-github-make-copilot-config)))
  (let ((keywords (warashi-agent-shell-contract-test--keywords
                   'agent-shell--set-default-config-options)))
    (dolist (keyword '(:config-options :on-options-set))
      (should (memq keyword keywords)))))

;;;; thought level の適用

(ert-deftest warashi-agent-shell-contract-test-state-is-function-and-variable ()
  "`agent-shell--state' を引数なしの関数としても buffer-local 変数としても引ける。
warashi-agent-shell は関数として、warashi-agent-shell-list は
`buffer-local-value' で変数として読む。"
  (should (equal '(0 . 0) (func-arity 'agent-shell--state)))
  (should (boundp 'agent-shell--state)))

(ert-deftest warashi-agent-shell-contract-test-state-holds-agent-config ()
  "state の :agent-config に、渡した agent config がそのまま載る。
thought level は agent config に push した独自キーを経由して session 確立
後に読み出すので、config が別物に組み替えられると効かなくなる。"
  (let* ((config (agent-shell-mock-agent-make-agent-config))
         (state (progn
                  ;; 本体と同じ順序で組む。push してから state に渡す。
                  (push (cons :warashi-thought-level "high") config)
                  (agent-shell--make-state :agent-config config))))
    (should (equal "high" (alist-get :warashi-thought-level
                                     (alist-get :agent-config state))))
    (should (equal "Mock" (map-nested-elt state '(:agent-config :buffer-name))))))

(ert-deftest warashi-agent-shell-contract-test-state-usage ()
  "state の :usage からコストを引ける。
session を確立していないので値は 0 だが、キーが揃っていることは見られる。"
  (let ((usage (map-elt (agent-shell--make-state) :usage)))
    (should (map-contains-key usage :cost-amount))
    (should (map-contains-key usage :cost-currency))
    (should (numberp (map-elt usage :cost-amount)))))

(ert-deftest warashi-agent-shell-contract-test-subscribe-to-keywords ()
  "`agent-shell-subscribe-to' が購読に使うキーワードを受ける。"
  (let ((keywords (warashi-agent-shell-contract-test--keywords 'agent-shell-subscribe-to)))
    (dolist (keyword '(:shell-buffer :event :on-event))
      (should (memq keyword keywords)))))

(ert-deftest warashi-agent-shell-contract-test-set-thought-level-keywords ()
  "`agent-shell--config-option-set-thought-level-id' が設定に使うキーワードを受ける。"
  (let ((keywords (warashi-agent-shell-contract-test--keywords
                   'agent-shell--config-option-set-thought-level-id)))
    (dolist (keyword '(:thought-level-id :on-failure))
      (should (memq keyword keywords)))))

;;;; buffer 名

(ert-deftest warashi-agent-shell-contract-test-project-name ()
  "`agent-shell--project-name' を引数なしで呼べ、`default-directory' の project 名を返す。
git-wit の memo と専用 clone の名前は、この戻り値を :filter-return advice で
差し替えている。引数を取るようになったり、`default-directory' 以外から
project を引くようになったりすると、両方とも効かなくなる。"
  ;; 引数をソースから読むのは、advice が付いた関数の `func-arity' は
  ;; advice 側の (0 . many) を返すため。
  (let ((loc (find-function-noselect 'agent-shell--project-name t)))
    (with-current-buffer (car loc)
      (goto-char (cdr loc))
      (should (null (nth 2 (read (current-buffer)))))))
  (let ((root (make-temp-file "project-name-contract-" t)))
    (unwind-protect
        (let ((default-directory (file-name-as-directory root)))
          (make-directory (expand-file-name ".git" root))
          (should (equal (file-name-nondirectory root)
                         (agent-shell--project-name))))
      (delete-directory root t))))

(ert-deftest warashi-agent-shell-contract-test-buffer-name-prefix ()
  "`agent-shell--buffer-name-prefix' を agent 名 1 つで呼べる。"
  (should (equal '(1 . 1) (func-arity 'agent-shell--buffer-name-prefix))))


;;;; コスト表示

(ert-deftest warashi-agent-shell-contract-test-shell-maker-busy ()
  "`shell-maker-busy' を引数なしで呼べ、shell 以外の buffer では signal する。
コストに実行中の印を付けるのに busy 判定を借りており、shell 外での signal
は `ignore-errors' で握り潰している。上流が nil を返すよう変えても印の出方
は変わらないが、引数を取るようになったり関数が消えたりすると効かなくなる。"
  (should (equal '(0 . 0) (func-arity 'shell-maker-busy)))
  (with-temp-buffer
    (should-error (shell-maker-busy))))


(provide 'warashi-agent-shell-contract-test)
;;; warashi-agent-shell-contract-test.el ends here

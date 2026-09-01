;;; warashi-agent-shell-test.el --- 起動と表示まわりのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-agent-shell-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'agent-shell)
(require 'warashi-agent-shell)

(defvar warashi-agent-shell-test--state nil
  "テスト用の `agent-shell--state' の戻り値。")

(defmacro warashi-agent-shell-test--with-state (state &rest body)
  "`agent-shell--state' が STATE を返す状況で BODY を実行する。"
  (declare (indent 1))
  `(let ((warashi-agent-shell-test--state ,state))
     (cl-letf (((symbol-function 'agent-shell--state)
                (lambda (&rest _) warashi-agent-shell-test--state)))
       ,@body)))

;;;; 単キーコマンドに入力メソッドを奪わせない

(ert-deftest warashi-agent-shell-test-self-insert-uses-remap ()
  "プロンプト上では remap 先 (入力メソッド) に打鍵を渡す。"
  (let ((called nil))
    (cl-letf (((symbol-function 'agent-shell--typing-at-prompt-p) (lambda () t))
              ((symbol-function 'command-remapping) (lambda (&rest _) 'remapped))
              ((symbol-function 'call-interactively)
               (lambda (cmd &rest _) (setq called cmd))))
      (warashi-agent-shell--self-insert-via-remap
       (lambda () (setq called 'original)))
      (should (eq 'remapped called)))))

(ert-deftest warashi-agent-shell-test-self-insert-passes-through ()
  "プロンプト外と remap 無しでは元のコマンドをそのまま走らせる。
入力メソッドを使っていない状態での挙動を変えないため。"
  (dolist (case '((nil t) (t nil)))
    (cl-letf* ((typing (car case))
               (remap (cadr case))
               ((symbol-function 'agent-shell--typing-at-prompt-p)
                (lambda () typing))
               ((symbol-function 'command-remapping) (lambda (&rest _) remap)))
      (let ((args nil))
        (warashi-agent-shell--self-insert-via-remap
         (lambda (&rest a) (setq args a)) 'x 'y)
        (should (equal '(x y) args))))))

(ert-deftest warashi-agent-shell-test-self-insert-advice-covers-commands ()
  "self-insert を直接呼ぶコマンドは全て remap 経由に差し替わる。"
  (let ((installed nil))
    (cl-letf (((symbol-function 'advice-add)
               (lambda (fn how advice) (push (list fn how advice) installed))))
      (warashi-agent-shell-install-self-insert-advice))
    (dolist (fn warashi-agent-shell-self-insert-commands)
      (should (member (list fn :around #'warashi-agent-shell--self-insert-via-remap)
                      installed)))
    ;; 一覧に挙げたコマンドが agent-shell 側から消えていたら気付けるようにする。
    (dolist (fn warashi-agent-shell-self-insert-commands)
      (should (fboundp fn)))))

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
    (should (equal "low" (alist-get :warashi-thought-level config)))))

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

;;;; git-wit の memo を buffer 名に出す

(defconst warashi-agent-shell-test--git-wit-json
  "[{\"id\":\"a1b2\",\"memo\":\"nskk の remap を直す\",\"path\":\"/home/me/wt/a1b2\"},
    {\"id\":\"c3d4\",\"memo\":\"\",\"path\":\"/home/me/wt/c3d4\"},
    {\"id\":\"e5f6\",\"path\":\"/home/me/wt/e5f6\"}]"
  "git-wit ls --json の出力を模した fixture。")

(defvar warashi-agent-shell-test--git-wit-calls nil
  "`warashi-agent-shell--git-wit-list' が呼ばれたディレクトリ。")

(defmacro warashi-agent-shell-test--with-git-wit (json &rest body)
  "git-wit が JSON を返し、repository 名が repo になる状況で BODY を実行する。
git-wit を呼んだディレクトリは `warashi-agent-shell-test--git-wit-calls' に積む。"
  (declare (indent 1))
  `(let ((warashi-agent-shell-test--git-wit-calls nil))
     (clrhash warashi-agent-shell--shell-name-cache)
     (cl-letf (((symbol-function 'warashi-agent-shell--git-wit-list)
                (lambda (directory)
                  (push directory warashi-agent-shell-test--git-wit-calls)
                  ,json))
               ((symbol-function 'warashi-agent-shell--repository-name)
                (lambda (_directory) "repo")))
       ,@body)))

(ert-deftest warashi-agent-shell-test-git-wit-memo-in ()
  "パスの一致する worktree の memo を返す。末尾のスラッシュは問わない。"
  (should (equal "nskk の remap を直す"
                 (warashi-agent-shell--git-wit-memo-in
                  warashi-agent-shell-test--git-wit-json "/home/me/wt/a1b2/")))
  (should (equal "nskk の remap を直す"
                 (warashi-agent-shell--git-wit-memo-in
                  warashi-agent-shell-test--git-wit-json "/home/me/wt/a1b2"))))

(ert-deftest warashi-agent-shell-test-git-wit-memo-in-unmanaged ()
  "git-wit の管理外のディレクトリでは memo を返さない。"
  (should-not (warashi-agent-shell--git-wit-memo-in
               warashi-agent-shell-test--git-wit-json "/home/me/src/other"))
  ;; worktree の中の子ディレクトリを前方一致で拾わない。
  (should-not (warashi-agent-shell--git-wit-memo-in
               warashi-agent-shell-test--git-wit-json "/home/me/wt/a1b2/sub")))

(ert-deftest warashi-agent-shell-test-git-wit-memo-in-blank ()
  "memo が空文字や未設定なら memo 無しとして扱う。"
  (should-not (warashi-agent-shell--git-wit-memo-in
               warashi-agent-shell-test--git-wit-json "/home/me/wt/c3d4"))
  (should-not (warashi-agent-shell--git-wit-memo-in
               warashi-agent-shell-test--git-wit-json "/home/me/wt/e5f6")))

(ert-deftest warashi-agent-shell-test-git-wit-memo-in-broken ()
  "git-wit を呼べなかったときと壊れた出力では memo 無しに落ちる。"
  (should-not (warashi-agent-shell--git-wit-memo-in nil "/home/me/wt/a1b2"))
  (should-not (warashi-agent-shell--git-wit-memo-in "" "/home/me/wt/a1b2"))
  (should-not (warashi-agent-shell--git-wit-memo-in "not json" "/home/me/wt/a1b2"))
  (should-not (warashi-agent-shell--git-wit-memo-in
               "{\"memo\":\"x\"}" "/home/me/wt/a1b2")))

(ert-deftest warashi-agent-shell-test-repository-name-in ()
  "common dir から repository 名を取る。"
  (should (equal "configurations"
                 (warashi-agent-shell--repository-name-in
                  "/home/me/ghq/github.com/warashi/configurations/.git")))
  ;; worktree から見た common dir は main の .git を指すので、その親が repo。
  (should (equal "configurations"
                 (warashi-agent-shell--repository-name-in
                  "/home/me/ghq/github.com/warashi/configurations/.git/")))
  ;; bare repo では common dir 自体が repo なので、親ではなく自分の名前を使う。
  (should (equal "configurations"
                 (warashi-agent-shell--repository-name-in
                  "/home/me/mirrors/configurations.git")))
  (should (equal "configurations"
                 (warashi-agent-shell--repository-name-in
                  "/home/me/mirrors/configurations"))))

(ert-deftest warashi-agent-shell-test-repository-name-in-broken ()
  "git を呼べなかったときは repository 名無しに落ちる。"
  (should-not (warashi-agent-shell--repository-name-in nil))
  (should-not (warashi-agent-shell--repository-name-in ""))
  (should-not (warashi-agent-shell--repository-name-in "/")))

(ert-deftest warashi-agent-shell-test-shell-name ()
  "repository 名と memo を並べた project 名を返す。"
  (warashi-agent-shell-test--with-git-wit warashi-agent-shell-test--git-wit-json
    (let ((default-directory "/ssh:host:/home/me/wt/a1b2/"))
      (should (equal "repo / nskk の remap を直す"
                     (warashi-agent-shell--shell-name)))
      ;; リモートでは接続先で git-wit を走らせ、パスはローカル部分で突き合わせる。
      (should (equal '("/ssh:host:/home/me/wt/a1b2/")
                     warashi-agent-shell-test--git-wit-calls)))
    ;; memo の無い worktree と管理外のディレクトリは差し替えない。
    (let ((default-directory "/ssh:host:/home/me/wt/c3d4/"))
      (should-not (warashi-agent-shell--shell-name)))
    (let ((default-directory "/ssh:host:/home/me/src/other/"))
      (should-not (warashi-agent-shell--shell-name)))))

(ert-deftest warashi-agent-shell-test-shell-name-without-repository ()
  "repository 名が取れないときは memo だけを使う。"
  (warashi-agent-shell-test--with-git-wit warashi-agent-shell-test--git-wit-json
    (cl-letf (((symbol-function 'warashi-agent-shell--repository-name)
               (lambda (_directory) nil)))
      (let ((default-directory "/ssh:host:/home/me/wt/a1b2/"))
        (should (equal "nskk の remap を直す"
                       (warashi-agent-shell--shell-name)))))))

(ert-deftest warashi-agent-shell-test-shell-name-cached ()
  "同じディレクトリでは git-wit を一度しか呼ばない。
header は再描画のたびに project 名を引くので、都度 process を起こさない。"
  (warashi-agent-shell-test--with-git-wit warashi-agent-shell-test--git-wit-json
    (let ((default-directory "/ssh:host:/home/me/wt/a1b2/"))
      (warashi-agent-shell--shell-name)
      (warashi-agent-shell--shell-name))
    ;; memo が無かったディレクトリも引き直さない。
    (let ((default-directory "/ssh:host:/home/me/wt/c3d4/"))
      (warashi-agent-shell--shell-name)
      (warashi-agent-shell--shell-name))
    (should (equal 2 (length warashi-agent-shell-test--git-wit-calls)))))

(ert-deftest warashi-agent-shell-test-project-name-with-memo ()
  "memo があれば project 名を差し替え、無ければそのまま返す。"
  (warashi-agent-shell-test--with-git-wit warashi-agent-shell-test--git-wit-json
    (let ((default-directory "/ssh:host:/home/me/wt/a1b2/"))
      (should (equal "repo / nskk の remap を直す"
                     (warashi-agent-shell--project-name-with-memo "a1b2"))))
    (let ((default-directory "/ssh:host:/home/me/src/other/"))
      (should (equal "other"
                     (warashi-agent-shell--project-name-with-memo "other"))))))

(provide 'warashi-agent-shell-test)
;;; warashi-agent-shell-test.el ends here

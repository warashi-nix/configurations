;;; warashi-agentel-test.el --- agentel の起動まわりのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-agentel-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
;; 起動コマンドが中で読み込むと、差し替えた `agentel-start' が戻されるため。
(require 'agentel)
(require 'warashi-agentel)

(defmacro warashi-agentel-test--capture-start (&rest body)
  "BODY を実行し、`agentel-start' に渡った引数の plist を返す。
`agentel-start' が呼ばれなければ nil を返す。"
  (declare (indent 0))
  `(let ((captured nil))
     (cl-letf (((symbol-function 'agentel-start)
                (lambda (&rest args) (setq captured args))))
       ,@body)
     captured))

(defmacro warashi-agentel-test--with-workspace (bindings &rest body)
  "一時的な専用作業領域を root にして BODY を実行する。
BINDINGS は (ROOT OUTSIDE) で、それぞれ root と領域外のディレクトリに束縛する。"
  (declare (indent 1))
  (let ((root (nth 0 bindings))
        (outside (nth 1 bindings)))
    `(let* ((,root (file-name-as-directory
                    (file-truename (make-temp-file "chelly-workspace-" t))))
            (,outside (file-name-as-directory
                       (file-truename (make-temp-file "chelly-outside-" t))))
            (warashi-chelly-workspace-root ,root))
       (unwind-protect
           (progn ,@body)
         (delete-directory ,root t)
         (delete-directory ,outside t)))))

;;;; 起動コマンド

(ert-deftest warashi-agentel-test-start-claude-options ()
  "model と effort を渡し、表示せずに default-directory で起動する。"
  (warashi-agentel-test--with-workspace (_root outside)
    (let* ((default-directory outside)
           (captured (warashi-agentel-test--capture-start
                       (warashi-agentel--start-claude "opus" "low"))))
      (should (equal outside (plist-get captured :cwd)))
      (should (equal "opus" (plist-get captured :model)))
      (should (equal "low" (plist-get captured :effort)))
      ;; 表示しないのは、起動を投げた後に window を取り返されないため。
      (should (plist-member captured :display))
      (should-not (plist-get captured :display)))))

(ert-deftest warashi-agentel-test-start-claude-inside-workspace-uses-real-path ()
  "専用領域では alias 経由でも実体のパスで起動する。"
  (warashi-agentel-test--with-workspace (root outside)
    (let* ((clone (expand-file-name "owner/repository/clone/" root))
           (alias (expand-file-name "workspace" outside)))
      (make-directory clone t)
      (make-symbolic-link root alias)
      (dolist (directory (list root clone
                               (expand-file-name "owner/repository/clone/" alias)))
        (let* ((default-directory (file-name-as-directory directory))
               (captured (warashi-agentel-test--capture-start
                           (warashi-agentel--start-claude "opus" "low"))))
          (should (equal (file-truename default-directory)
                         (plist-get captured :cwd))))))))

(ert-deftest warashi-agentel-test-start-claude-refuses-symlink-escape ()
  "専用領域に見えて実体が外なら、本人の credential で起動しない。"
  (warashi-agentel-test--with-workspace (root outside)
    (let ((escape (expand-file-name "escape" root)))
      (make-symbolic-link outside escape)
      (let ((default-directory (file-name-as-directory escape))
            (started nil))
        (cl-letf (((symbol-function 'agentel-start)
                   (lambda (&rest _) (setq started t))))
          (should-error (warashi-agentel--start-claude "opus" "low")
                        :type 'user-error))
        ;; 起動後に拒否すると、中身の無い session buffer が残る。
        (should-not started)))))

(ert-deftest warashi-agentel-test-start-claude-refuses-remote ()
  "TRAMP 先では起動しない。"
  (let ((default-directory "/ssh:example.invalid:/tmp/")
        (started nil))
    (cl-letf (((symbol-function 'agentel-start)
               (lambda (&rest _) (setq started t))))
      (should-error (warashi-agentel--start-claude "opus" "low")
                    :type 'user-error))
    (should-not started)))

(ert-deftest warashi-agentel-test-define-claude-variants ()
  "variant ごとにコマンドと eshell 用の関数を定義する。"
  (let ((warashi-agentel-variants nil))
    (warashi-agentel-define-claude-variants
     (warashi-agentel-test-variant "test-model" "high"))
    (should (commandp 'warashi-agentel-claude-warashi-agentel-test-variant))
    (let ((args nil))
      (cl-letf (((symbol-function 'warashi-agentel--start-claude)
                 (lambda (&rest a)
                   (setq args a)
                   (agentel-session--make))))
        (funcall 'eshell/claude-warashi-agentel-test-variant))
      (should (equal '("test-model" "high") args)))))

(ert-deftest warashi-agentel-test-eshell-reports-started-session ()
  "eshell 用の関数は session ではなく、起動した buffer を示す一行を返す。"
  (let ((warashi-agentel-variants nil)
        (buffer (generate-new-buffer "*agentel: test*")))
    (unwind-protect
        (progn
          (warashi-agentel-define-claude-variants
           (warashi-agentel-test-variant "test-model" "high"))
          (cl-letf (((symbol-function 'warashi-agentel--start-claude)
                     (lambda (&rest _) (agentel-session--make :buffer buffer))))
            (should (equal "claude-warashi-agentel-test-variant: started *agentel: test*"
                           (funcall 'eshell/claude-warashi-agentel-test-variant)))))
      (kill-buffer buffer))))

;;;; project-switch からの起動

(ert-deftest warashi-agentel-test-variants-registered ()
  "variant は claude の別が付いた名前で定義順に一覧へ載る。"
  (let ((warashi-agentel-variants nil))
    (warashi-agentel-define-claude-variants
     (warashi-agentel-test-first "test-model" "high")
     (warashi-agentel-test-second "test-model" "low"))
    (should (equal
             '(("claude-warashi-agentel-test-first"
                . warashi-agentel-claude-warashi-agentel-test-first)
               ("claude-warashi-agentel-test-second"
                . warashi-agentel-claude-warashi-agentel-test-second))
             warashi-agentel-variants))))

(ert-deftest warashi-agentel-test-variants-not-duplicated ()
  "同じ名前で定義し直しても一覧は増えない。
init.org を評価し直すたびに候補が伸びると選べなくなるため。"
  (let ((warashi-agentel-variants nil))
    (warashi-agentel-define-claude-variants
     (warashi-agentel-test-redefined "test-model" "high"))
    (warashi-agentel-define-claude-variants
     (warashi-agentel-test-redefined "other-model" "low"))
    (should (equal 1 (length warashi-agentel-variants)))))

(ert-deftest warashi-agentel-test-project-switch-starts-and-reopens ()
  "選んだ variant を起動し、同じ project のディスパッチを開き直す。"
  (let ((warashi-agentel-variants
         '(("claude-test" . warashi-agentel-test--variant-command)))
        (started nil)
        (reopened nil)
        (project-current-directory-override "/tmp/warashi-agentel-test/"))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "claude-test"))
              ((symbol-function 'warashi-agentel-test--variant-command)
               (lambda () (setq started t)))
              ((symbol-function 'project-switch-project)
               (lambda (dir) (setq reopened dir))))
      (warashi-agentel-project-switch))
    (should started)
    ;; 起動しただけだと default-directory が元の project に戻り、続けて
    ;; magit を開くのに project を選び直すことになる。
    (should (equal "/tmp/warashi-agentel-test/" reopened))))

(ert-deftest warashi-agentel-test-project-switch-outside-dispatch ()
  "ディスパッチ外から呼んだときはメニューを開かない。"
  (let ((warashi-agentel-variants
         '(("claude-test" . warashi-agentel-test--variant-command)))
        (started nil)
        (reopened nil)
        (project-current-directory-override nil))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "claude-test"))
              ((symbol-function 'warashi-agentel-test--variant-command)
               (lambda () (setq started t)))
              ((symbol-function 'project-switch-project)
               (lambda (dir) (setq reopened dir))))
      (warashi-agentel-project-switch))
    (should started)
    (should-not reopened)))

;;;; 専用 runner への振り分け

(ert-deftest warashi-agentel-test-command-prefix-routes-by-directory ()
  "専用領域の中だけ専用 runner を使い、外では通常の prefix を使う。"
  (warashi-agentel-test--with-workspace (root outside)
    (let ((warashi-agentel-ordinary-command-prefix '("ordinary" "run")))
      (should (equal '("chelly-agent" "run" "--")
                     (warashi-agentel-command-prefix root)))
      (should (equal '("ordinary" "run")
                     (warashi-agentel-command-prefix outside))))))

(ert-deftest warashi-agentel-test-command-prefix-refuses-symlink-escape ()
  "/resume など起動コマンドを通らない経路でも、逸脱した path では動かさない。"
  (warashi-agentel-test--with-workspace (root outside)
    (let ((escape (expand-file-name "escape" root)))
      (make-symbolic-link outside escape)
      (should-error (warashi-agentel-command-prefix
                     (file-name-as-directory escape))
                    :type 'user-error))))

(provide 'warashi-agentel-test)
;;; warashi-agentel-test.el ends here

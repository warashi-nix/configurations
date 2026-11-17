;;; warashi-chelly-workspace-test.el --- 専用作業領域のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-chelly-workspace-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'warashi-chelly-workspace)

(defmacro warashi-chelly-workspace-test--with-root (root &rest body)
  "一時ディレクトリを root にして BODY を実行し、後で消す。
ROOT はその一時ディレクトリを束縛する変数名。"
  (declare (indent 1))
  `(let* ((,root (make-temp-file "chelly-workspace-" t))
          (warashi-chelly-workspace-root ,root))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,root t))))

(defconst warashi-chelly-workspace-test--project "github.com/Warashi/configurations"
  "本人の ghq root からの path。専用領域でも clone をこの下に置く。")

(defun warashi-chelly-workspace-test--clone (root id &optional project)
  "ROOT の下に PROJECT (既定は configurations) の ID の clone を作り、場所を返す。"
  (let ((clone (expand-file-name
                (concat (or project warashi-chelly-workspace-test--project) "/" id)
                root)))
    (make-directory (expand-file-name ".git" clone) t)
    clone))

(ert-deftest warashi-chelly-workspace-test-parse-clone ()
  "ghq の path の下で .git を持つディレクトリを clone と見て (project . name) を返す。"
  (warashi-chelly-workspace-test--with-root root
    (let ((clone (warashi-chelly-workspace-test--clone root "main")))
      (make-directory (expand-file-name "sub" clone) t)
      (make-directory (expand-file-name "deps/lib/.git" clone) t)
      (should (equal (cons warashi-chelly-workspace-test--project "main")
                     (warashi-chelly-workspace-parse clone)))
      (should (equal (cons warashi-chelly-workspace-test--project "main")
                     (warashi-chelly-workspace-parse (file-name-as-directory clone))))
      ;; ghq の path の途中は clone の置き場で clone ではない。
      (dolist (place '("github.com" "github.com/Warashi" "github.com/Warashi/configurations"))
        (should-not (warashi-chelly-workspace-parse (expand-file-name place root))))
      ;; clone の下のディレクトリも、clone の中の submodule も clone ではない。
      (should-not (warashi-chelly-workspace-parse (expand-file-name "sub" clone)))
      (should-not (warashi-chelly-workspace-parse (expand-file-name "deps/lib" clone)))
      (should-not (warashi-chelly-workspace-parse root)))))

;; 日本語や空白を含む名前は、chelly-handoff が x- と UTF-8 の 16 進にした
;; ディレクトリに置く。
(defconst warashi-chelly-workspace-test--hex-id
  "x-e383ade382b0e382a4e383b320e4bfaee6ada3"
  "\"ログイン 修正\" の ID。")

(ert-deftest warashi-chelly-workspace-test-parse-decodes-hex-id ()
  "16 進の ID のディレクトリからは元の名前を返す。"
  (warashi-chelly-workspace-test--with-root root
    (let ((clone (warashi-chelly-workspace-test--clone
                  root warashi-chelly-workspace-test--hex-id))
          (ascii (warashi-chelly-workspace-test--clone root "x-zz")))
      (should (equal (cons warashi-chelly-workspace-test--project "ログイン 修正")
                     (warashi-chelly-workspace-parse clone)))
      ;; 16 進でなければ chelly-handoff が作った ID ではないので、そのまま返す。
      (should (equal (cons warashi-chelly-workspace-test--project "x-zz")
                     (warashi-chelly-workspace-parse ascii))))))

(ert-deftest warashi-chelly-workspace-test-parse-outside ()
  "専用領域の外やリモートでは nil。"
  (warashi-chelly-workspace-test--with-root root
    (let ((outside (make-temp-file "chelly-outside-" t)))
      (unwind-protect
          (should-not (warashi-chelly-workspace-parse
                       (warashi-chelly-workspace-test--clone outside "main")))
        (delete-directory outside t)))
    (should-not (warashi-chelly-workspace-parse
                 "/ssh:workbench:/srv/chelly-workspaces/github.com/Warashi/configurations/main/"))))

(ert-deftest warashi-chelly-workspace-test-parse-resolves-symlink ()
  "root や clone への symlink 経由でも実体で判定する。"
  (warashi-chelly-workspace-test--with-root root
    (let ((link (concat (make-temp-file "chelly-link-") "-dir")))
      (warashi-chelly-workspace-test--clone root "main")
      (make-symbolic-link root link)
      (unwind-protect
          (should (equal (cons warashi-chelly-workspace-test--project "main")
                         (warashi-chelly-workspace-parse
                          (expand-file-name
                           (concat warashi-chelly-workspace-test--project "/main") link))))
        (delete-file link)))))

;;;; project 名

(defmacro warashi-chelly-workspace-test--with-project-name (&rest body)
  "project 名の差し替えを有効にして BODY を実行し、後で外す。"
  (declare (indent 0))
  `(unwind-protect
       (progn
         (warashi-chelly-workspace-install-project-name)
         ,@body)
     (advice-remove 'project-name #'warashi-chelly-workspace--project-name)))

(defun warashi-chelly-workspace-test--project-name (directory)
  "DIRECTORY を含む project の名前を返す。"
  (let ((default-directory (file-name-as-directory directory)))
    (project-name (project-current))))

(ert-deftest warashi-chelly-workspace-test-project-name-includes-repository ()
  "専用 clone の project 名は <repo> / <handoff 名> (chelly) になり、
別 repo の同名 handoff と区別できる。"
  (warashi-chelly-workspace-test--with-root root
    (let ((clone (warashi-chelly-workspace-test--clone root "main"))
          (other (warashi-chelly-workspace-test--clone
                  root "main" "github.com/Warashi/brainium")))
      (make-directory (expand-file-name "sub" clone))
      (warashi-chelly-workspace-test--with-project-name
        (should (equal "configurations / main (chelly)"
                       (warashi-chelly-workspace-test--project-name clone)))
        ;; clone の下のディレクトリから見ても同じ名前になる。
        (should (equal "configurations / main (chelly)"
                       (warashi-chelly-workspace-test--project-name
                        (expand-file-name "sub" clone))))
        (should (equal "brainium / main (chelly)"
                       (warashi-chelly-workspace-test--project-name other)))))))

(ert-deftest warashi-chelly-workspace-test-project-name-decodes-hex-id ()
  "16 進の ID の clone の project 名には元の名前を出す。"
  (warashi-chelly-workspace-test--with-root root
    (let ((clone (warashi-chelly-workspace-test--clone
                  root warashi-chelly-workspace-test--hex-id)))
      (warashi-chelly-workspace-test--with-project-name
        (should (equal "configurations / ログイン 修正 (chelly)"
                       (warashi-chelly-workspace-test--project-name clone)))))))

(ert-deftest warashi-chelly-workspace-test-project-name-leaves-others ()
  "専用領域の 1 段目と領域外の project 名は変えない。"
  (warashi-chelly-workspace-test--with-root root
    (let ((outside (make-temp-file "chelly-outside-" t)))
      (unwind-protect
          (progn
            (dolist (directory (list (expand-file-name "configurations" root)
                                     (expand-file-name "main" outside)))
              (make-directory (expand-file-name ".git" directory) t))
            (warashi-chelly-workspace-test--with-project-name
              (should (equal "configurations"
                             (warashi-chelly-workspace-test--project-name
                              (expand-file-name "configurations" root))))
              (should (equal "main"
                             (warashi-chelly-workspace-test--project-name
                              (expand-file-name "main" outside))))))
        (delete-directory outside t)))))

(ert-deftest warashi-chelly-workspace-test-project-name-skips-remote ()
  "リモートの project では専用領域の判定に入らず名前をそのまま返す。"
  (warashi-chelly-workspace-test--with-project-name
    (cl-letf (((symbol-function 'file-truename)
               (lambda (&rest _) (ert-fail "file-truename was called for a remote project"))))
      (should (equal "main"
                     (project-name
                      '(vc Git "/ssh:workbench:/srv/chelly-workspaces/github.com/Warashi/configurations/main/")))))))

;;;; 本人の repository から見た clone の列挙と作成

(defvar warashi-chelly-workspace-test--output ""
  "stub した chelly-handoff の出力。")

(defvar warashi-chelly-workspace-test--calls nil
  "stub した call-process の呼び出し。(default-directory program . args)。")

(defmacro warashi-chelly-workspace-test--with-handoff (status &rest body)
  "chelly-handoff と専用領域が在って STATUS で終わる状況で BODY を実行する。
chelly-handoff は `warashi-chelly-workspace-test--output' を出力する。"
  (declare (indent 1))
  `(let ((warashi-chelly-workspace-test--calls nil)
         (warashi-chelly-workspace-root temporary-file-directory)
         (displayed nil))
     (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/bin/chelly-handoff"))
               ((symbol-function 'display-buffer) (lambda (buffer &rest _) (setq displayed buffer)))
               ((symbol-function 'call-process)
                (lambda (program _infile destination _display &rest args)
                  (push (cons default-directory (cons program args))
                        warashi-chelly-workspace-test--calls)
                  (let ((buffer (if (consp destination) (car destination) destination)))
                    (with-current-buffer (if (eq buffer t) (current-buffer) buffer)
                      (insert warashi-chelly-workspace-test--output)))
                  ,status)))
       (ignore displayed)
       ,@body)))

(ert-deftest warashi-chelly-workspace-test-list-clones-of-repository ()
  "chelly-handoff where が示す置き場にある clone を (name . dir) で返す。"
  (warashi-chelly-workspace-test--with-root root
    (let ((place (expand-file-name warashi-chelly-workspace-test--project root)))
      (make-directory (expand-file-name "main" place) t)
      (make-directory (expand-file-name "feature-x" place) t)
      (make-directory (expand-file-name ".hidden" place) t)
      (make-directory (expand-file-name "github.com/Warashi/other/main" root) t)
      (with-temp-file (expand-file-name "note.txt" place))
      (let ((warashi-chelly-workspace-test--output (concat place "\n")))
        (warashi-chelly-workspace-test--with-handoff 0
          (setq warashi-chelly-workspace-root root)
          (should (equal (list (cons "feature-x"
                                     (file-name-as-directory
                                      (expand-file-name "feature-x" place)))
                               (cons "main"
                                     (file-name-as-directory
                                      (expand-file-name "main" place))))
                         (warashi-chelly-workspace-list
                          "/home/me/ghq/github.com/Warashi/configurations")))
          (should (equal '(("/home/me/ghq/github.com/Warashi/configurations/"
                            "chelly-handoff" "where"))
                         warashi-chelly-workspace-test--calls))))
      (let ((warashi-chelly-workspace-test--output
             (concat (expand-file-name "github.com/Warashi/none" root) "\n")))
        (warashi-chelly-workspace-test--with-handoff 0
          (setq warashi-chelly-workspace-root root)
          (should-not (warashi-chelly-workspace-list
                       "/home/me/ghq/github.com/Warashi/none")))))))

(ert-deftest warashi-chelly-workspace-test-list-decodes-hex-id ()
  "16 進の ID の clone は元の名前で返す。"
  (warashi-chelly-workspace-test--with-root root
    (let* ((clone (warashi-chelly-workspace-test--clone
                   root warashi-chelly-workspace-test--hex-id))
           (warashi-chelly-workspace-test--output
            (concat (directory-file-name (file-name-directory clone)) "\n")))
      (warashi-chelly-workspace-test--with-handoff 0
        (setq warashi-chelly-workspace-root root)
        (should (equal (list (cons "ログイン 修正" (file-name-as-directory clone)))
                       (warashi-chelly-workspace-list
                        "/home/me/ghq/github.com/Warashi/configurations")))))))

(ert-deftest warashi-chelly-workspace-test-list-without-place ()
  "専用領域の無いホスト、ghq の外の repository、リモートでは nil。"
  (let ((warashi-chelly-workspace-root "/nonexistent/chelly-workspaces/"))
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/bin/chelly-handoff"))
              ((symbol-function 'call-process)
               (lambda (&rest _) (ert-fail "chelly-handoff was called"))))
      (should-not (warashi-chelly-workspace-list
                   "/home/me/ghq/github.com/Warashi/configurations"))))
  (let ((warashi-chelly-workspace-test--output "chelly-handoff: not under ghq root\n"))
    (warashi-chelly-workspace-test--with-handoff 1
      (should-not (warashi-chelly-workspace-list "/home/me/loose"))
      (should-not (warashi-chelly-workspace-list "/ssh:host:/home/me/ghq/x"))
      (should (equal 1 (length warashi-chelly-workspace-test--calls))))))

(ert-deftest warashi-chelly-workspace-test-create-runs-handoff-in-repository ()
  "create は本人の repository の中で chelly-handoff create NAME を走らせ、
最終行に出た clone の場所を返す。"
  (let ((warashi-chelly-workspace-test--output
         (concat "chelly-handoff: submodule deps is not initialized here; not sent\n"
                 "/srv/chelly-workspaces/github.com/Warashi/configurations/"
                 warashi-chelly-workspace-test--hex-id "\n")))
    (warashi-chelly-workspace-test--with-handoff 0
      (should (equal (concat "/srv/chelly-workspaces/github.com/Warashi/configurations/"
                             warashi-chelly-workspace-test--hex-id "/")
                     (warashi-chelly-workspace-create
                      "/home/me/ghq/github.com/Warashi/configurations" "ログイン 修正")))
      (should (equal '(("/home/me/ghq/github.com/Warashi/configurations/"
                        "chelly-handoff" "create" "ログイン 修正"))
                     warashi-chelly-workspace-test--calls)))))

(ert-deftest warashi-chelly-workspace-test-create-from-commit ()
  "COMMIT を渡すと、HEAD ではなくその commit から作らせる。"
  (let ((warashi-chelly-workspace-test--output
         "/srv/chelly-workspaces/github.com/Warashi/configurations/pr-12\n"))
    (warashi-chelly-workspace-test--with-handoff 0
      (warashi-chelly-workspace-create
       "/home/me/ghq/github.com/Warashi/configurations" "pr-12" "0123abcd")
      (should (equal '(("/home/me/ghq/github.com/Warashi/configurations/"
                        "chelly-handoff" "create" "pr-12" "0123abcd"))
                     warashi-chelly-workspace-test--calls)))))

(ert-deftest warashi-chelly-workspace-test-create-signals-on-failure ()
  "create が失敗したら出力の buffer を見せて user-error を出す。"
  (warashi-chelly-workspace-test--with-handoff 1
    (should-error (warashi-chelly-workspace-create
                   "/home/me/ghq/github.com/Warashi/configurations" "feature-x")
                  :type 'user-error)
    (should (bufferp displayed))))

(ert-deftest warashi-chelly-workspace-test-create-refuses-without-handoff ()
  "chelly-handoff か専用領域の無いホストとリモートの repository では走らせずに拒否する。"
  (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil))
            ((symbol-function 'call-process)
             (lambda (&rest _) (ert-fail "chelly-handoff was called"))))
    (should-not (warashi-chelly-workspace-available-p))
    (should-error (warashi-chelly-workspace-create "/home/me/repo" "x") :type 'user-error))
  ;; chelly-handoff は全ホストに入るが、専用領域の無いホストもある。
  (let ((warashi-chelly-workspace-root "/nonexistent/chelly-workspaces/"))
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/bin/chelly-handoff"))
              ((symbol-function 'call-process)
               (lambda (&rest _) (ert-fail "chelly-handoff was called"))))
      (should-not (warashi-chelly-workspace-available-p))
      (should-error (warashi-chelly-workspace-create "/home/me/repo" "x") :type 'user-error)))
  (warashi-chelly-workspace-test--with-handoff 0
    (should-error (warashi-chelly-workspace-create "/ssh:host:/home/me/repo" "x")
                  :type 'user-error)
    (should-not warashi-chelly-workspace-test--calls)))

(provide 'warashi-chelly-workspace-test)
;;; warashi-chelly-workspace-test.el ends here

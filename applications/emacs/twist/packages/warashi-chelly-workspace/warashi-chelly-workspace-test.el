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

(ert-deftest warashi-chelly-workspace-test-parse-clone ()
  "root 直下の 2 段目だけを clone と見て (repo . name) を返す。"
  (warashi-chelly-workspace-test--with-root root
    (let ((clone (expand-file-name "configurations/main" root)))
      (make-directory (expand-file-name "sub" clone) t)
      (should (equal '("configurations" . "main")
                     (warashi-chelly-workspace-parse clone)))
      (should (equal '("configurations" . "main")
                     (warashi-chelly-workspace-parse (file-name-as-directory clone))))
      ;; 1 段目は repo 名の置き場で clone ではない。
      (should-not (warashi-chelly-workspace-parse
                   (expand-file-name "configurations" root)))
      ;; clone の下のディレクトリも clone ではない。
      (should-not (warashi-chelly-workspace-parse
                   (expand-file-name "sub" clone)))
      (should-not (warashi-chelly-workspace-parse root)))))

(ert-deftest warashi-chelly-workspace-test-parse-outside ()
  "専用領域の外やリモートでは nil。"
  (warashi-chelly-workspace-test--with-root root
    (let ((outside (make-temp-file "chelly-outside-" t)))
      (unwind-protect
          (progn
            (make-directory (expand-file-name "configurations/main" outside) t)
            (should-not (warashi-chelly-workspace-parse
                         (expand-file-name "configurations/main" outside))))
        (delete-directory outside t)))
    (should-not (warashi-chelly-workspace-parse
                 "/ssh:workbench:/srv/chelly-workspaces/configurations/main/"))))

(ert-deftest warashi-chelly-workspace-test-parse-resolves-symlink ()
  "root や clone への symlink 経由でも実体で判定する。"
  (warashi-chelly-workspace-test--with-root root
    (let ((link (concat (make-temp-file "chelly-link-") "-dir")))
      (make-directory (expand-file-name "configurations/main" root) t)
      (make-symbolic-link root link)
      (unwind-protect
          (should (equal '("configurations" . "main")
                         (warashi-chelly-workspace-parse
                          (expand-file-name "configurations/main" link))))
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
    (let ((clone (expand-file-name "configurations/main" root))
          (other (expand-file-name "brainium/main" root)))
      (dolist (directory (list clone other))
        (make-directory (expand-file-name ".git" directory) t))
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
                      '(vc Git "/ssh:workbench:/srv/chelly-workspaces/configurations/main/")))))))

;;;; 本人の repository から見た clone の列挙と作成

(ert-deftest warashi-chelly-workspace-test-list-clones-of-repository ()
  "repository の basename と同じ置き場にある clone を (name . dir) で返す。"
  (warashi-chelly-workspace-test--with-root root
    (make-directory (expand-file-name "configurations/main" root) t)
    (make-directory (expand-file-name "configurations/feature-x" root) t)
    (make-directory (expand-file-name "configurations/.hidden" root) t)
    (make-directory (expand-file-name "other/main" root) t)
    (with-temp-file (expand-file-name "configurations/note.txt" root))
    (should (equal (list (cons "feature-x"
                               (file-name-as-directory
                                (expand-file-name "configurations/feature-x" root)))
                         (cons "main"
                               (file-name-as-directory
                                (expand-file-name "configurations/main" root))))
                   (warashi-chelly-workspace-list
                    "/home/me/ghq/github.com/Warashi/configurations")))
    ;; 末尾のスラッシュは問わない。
    (should (equal 2 (length (warashi-chelly-workspace-list
                              "/home/me/ghq/github.com/Warashi/configurations/"))))
    (should-not (warashi-chelly-workspace-list "/home/me/ghq/github.com/Warashi/none"))))

(ert-deftest warashi-chelly-workspace-test-list-without-root ()
  "専用領域の無いホストでは nil。"
  (let ((warashi-chelly-workspace-root "/nonexistent/chelly-workspaces/"))
    (should-not (warashi-chelly-workspace-list "/home/me/ghq/github.com/Warashi/configurations"))))

(ert-deftest warashi-chelly-workspace-test-path ()
  "clone のディレクトリは <root>/<repo>/<name>/。"
  (let ((warashi-chelly-workspace-root "/srv/chelly-workspaces/"))
    (should (equal "/srv/chelly-workspaces/configurations/main/"
                   (warashi-chelly-workspace-path
                    "/home/me/ghq/github.com/Warashi/configurations" "main")))))

(defvar warashi-chelly-workspace-test--calls nil
  "stub した call-process の呼び出し。(default-directory program . args)。")

(defmacro warashi-chelly-workspace-test--with-handoff (status &rest body)
  "chelly-handoff と専用領域が在って STATUS で終わる状況で BODY を実行する。"
  (declare (indent 1))
  `(let ((warashi-chelly-workspace-test--calls nil)
         (warashi-chelly-workspace-root temporary-file-directory)
         (displayed nil))
     (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/bin/chelly-handoff"))
               ((symbol-function 'display-buffer) (lambda (buffer &rest _) (setq displayed buffer)))
               ((symbol-function 'call-process)
                (lambda (program _infile _destination _display &rest args)
                  (push (cons default-directory (cons program args))
                        warashi-chelly-workspace-test--calls)
                  ,status)))
       (ignore displayed)
       ,@body)))

(ert-deftest warashi-chelly-workspace-test-create-runs-handoff-in-repository ()
  "create は本人の repository の中で chelly-handoff create NAME を走らせ、clone の場所を返す。"
  (warashi-chelly-workspace-test--with-handoff 0
    (should (equal (warashi-chelly-workspace-path
                    "/home/me/ghq/github.com/Warashi/configurations" "feature-x")
                   (warashi-chelly-workspace-create
                    "/home/me/ghq/github.com/Warashi/configurations" "feature-x")))
    (should (equal '(("/home/me/ghq/github.com/Warashi/configurations/"
                      "chelly-handoff" "create" "feature-x"))
                   warashi-chelly-workspace-test--calls))))

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
  ;; chelly-handoff は全ホストに入るが、専用領域は workbench にしか無い。
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

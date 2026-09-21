;;; warashi-git-wit-test.el --- git-wit 呼び出しのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-git-wit-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'warashi-git-wit)

(defconst warashi-git-wit-test--ls-json
  "[{\"id\":\"a1b2\",\"memo\":\"nskk の remap を直す\",\"path\":\"/home/me/wt/a1b2\",
     \"branch\":null,\"state\":\"Active\"},
    {\"id\":\"c3d4\",\"memo\":\"\",\"path\":\"/home/me/wt/c3d4\"}]"
  "git-wit ls --json の出力を模した fixture。")

(defmacro warashi-git-wit-test--with-process (output status &rest body)
  "git-wit が OUTPUT を出して STATUS で終わる状況で BODY を実行する。
呼び出しの引数は `warashi-git-wit-test--calls' に積む。"
  (declare (indent 2))
  `(let ((warashi-git-wit-test--calls nil))
     (cl-letf (((symbol-function 'process-file)
                (lambda (program _infile _destination _display &rest args)
                  (push (cons default-directory (cons program args))
                        warashi-git-wit-test--calls)
                  (insert ,output)
                  ,status)))
       ,@body)))

(defvar warashi-git-wit-test--calls nil
  "stub した process-file の呼び出し。(default-directory program . args)。")

(ert-deftest warashi-git-wit-test-list-parses-json ()
  "ls --json の出力を worktree ごとの alist にして、null は nil にする。"
  (warashi-git-wit-test--with-process warashi-git-wit-test--ls-json 0
    (let ((worktrees (warashi-git-wit-list "/home/me/repo/")))
      (should (= 2 (length worktrees)))
      (let-alist (car worktrees)
        (should (equal .id "a1b2"))
        (should (equal .memo "nskk の remap を直す"))
        (should (equal .path "/home/me/wt/a1b2"))
        (should-not .branch)
        (should (equal .state "Active")))
      ;; 対象ディレクトリの中で ls を走らせる。
      (should (equal '(("/home/me/repo/" "git-wit" "ls" "--json"))
                     warashi-git-wit-test--calls)))))

(ert-deftest warashi-git-wit-test-list-falls-back-to-nil ()
  "git-wit を呼べないときと壊れた出力では nil に落ちる。"
  (warashi-git-wit-test--with-process "Error: not a git repository" 1
    (should-not (warashi-git-wit-list "/home/me/")))
  (warashi-git-wit-test--with-process "" 0
    (should-not (warashi-git-wit-list "/home/me/repo/")))
  (warashi-git-wit-test--with-process "not json" 0
    (should-not (warashi-git-wit-list "/home/me/repo/")))
  (warashi-git-wit-test--with-process "{\"memo\":\"x\"}" 0
    (should-not (warashi-git-wit-list "/home/me/repo/")))
  (cl-letf (((symbol-function 'process-file)
             (lambda (&rest _) (signal 'file-missing '("git-wit")))))
    (should-not (warashi-git-wit-list "/home/me/repo/"))))

(ert-deftest warashi-git-wit-test-list-empty ()
  "worktree の無い repository では空リスト。"
  (warashi-git-wit-test--with-process "[]" 0
    (should (equal nil (warashi-git-wit-list "/home/me/repo/")))))

(ert-deftest warashi-git-wit-test-add-returns-path ()
  "add は git の進行表示の後の最終行 ID<TAB>PATH からパスを取る。"
  (warashi-git-wit-test--with-process
      "Preparing worktree (detached HEAD c8ac4f3)\nHEAD is now at c8ac4f3 init\n01a0c30e\t/home/me/wt/01a0c30e\n"
      0
    (should (equal "/home/me/wt/01a0c30e"
                   (warashi-git-wit-add "/home/me/repo/" "試し memo")))
    (should (equal '(("/home/me/repo/" "git-wit" "add" "試し memo"))
                   warashi-git-wit-test--calls))))

(ert-deftest warashi-git-wit-test-add-signals-on-failure ()
  "add が失敗したら出力を添えて user-error を出す。"
  (warashi-git-wit-test--with-process "Error: run add: something" 1
    (let ((err (should-error (warashi-git-wit-add "/home/me/repo/" "m")
                             :type 'user-error)))
      (should (string-match-p "something" (cadr err)))))
  (warashi-git-wit-test--with-process "no tab separated line" 0
    (should-error (warashi-git-wit-add "/home/me/repo/" "m") :type 'user-error)))

(provide 'warashi-git-wit-test)
;;; warashi-git-wit-test.el ends here

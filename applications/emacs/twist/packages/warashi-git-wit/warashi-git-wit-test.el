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

;;;; project 名

(defconst warashi-git-wit-test--worktrees
  '(((id . "a1b2") (memo . "nskk の remap を直す") (path . "/home/me/wt/a1b2"))
    ((id . "c3d4") (memo . "") (path . "/home/me/wt/c3d4"))
    ((id . "e5f6") (path . "/home/me/wt/e5f6")))
  "`warashi-git-wit-list' が返す worktree 一覧を模した fixture。")

(defvar warashi-git-wit-test--list-calls nil
  "`warashi-git-wit-list' が呼ばれたディレクトリ。")

(defmacro warashi-git-wit-test--with-worktrees (worktrees &rest body)
  "git-wit が WORKTREES を返し、repository 名が repo になる状況で BODY を実行する。
`warashi-git-wit-list' を呼んだディレクトリは `warashi-git-wit-test--list-calls'
に積む。project 名の差し替えを有効にし、後で外す。"
  (declare (indent 1))
  `(let ((warashi-git-wit-test--list-calls nil))
     (clrhash warashi-git-wit--project-name-cache)
     (cl-letf (((symbol-function 'warashi-git-wit-list)
                (lambda (directory)
                  (push directory warashi-git-wit-test--list-calls)
                  ,worktrees))
               ((symbol-function 'warashi-git-wit--repository-name)
                (lambda (_directory) "repo")))
       (unwind-protect
           (progn
             (warashi-git-wit-install-project-name)
             ,@body)
         (advice-remove 'project-name #'warashi-git-wit--project-name)))))

(ert-deftest warashi-git-wit-test-memo-in ()
  "パスの一致する worktree の memo を返す。末尾のスラッシュは問わない。"
  (should (equal "nskk の remap を直す"
                 (warashi-git-wit--memo-in
                  warashi-git-wit-test--worktrees "/home/me/wt/a1b2/")))
  (should (equal "nskk の remap を直す"
                 (warashi-git-wit--memo-in
                  warashi-git-wit-test--worktrees "/home/me/wt/a1b2"))))

(ert-deftest warashi-git-wit-test-memo-in-unmanaged ()
  "git-wit の管理外のディレクトリと空の memo では memo を返さない。"
  (should-not (warashi-git-wit--memo-in
               warashi-git-wit-test--worktrees "/home/me/src/other"))
  ;; worktree の中の子ディレクトリを前方一致で拾わない。
  (should-not (warashi-git-wit--memo-in
               warashi-git-wit-test--worktrees "/home/me/wt/a1b2/sub"))
  (should-not (warashi-git-wit--memo-in
               warashi-git-wit-test--worktrees "/home/me/wt/c3d4"))
  (should-not (warashi-git-wit--memo-in
               warashi-git-wit-test--worktrees "/home/me/wt/e5f6"))
  ;; git-wit を呼べなかったとき (一覧が nil) も memo 無し。
  (should-not (warashi-git-wit--memo-in nil "/home/me/wt/a1b2")))

(ert-deftest warashi-git-wit-test-repository-name-in ()
  "common dir から repository 名を取る。"
  (should (equal "configurations"
                 (warashi-git-wit--repository-name-in
                  "/home/me/ghq/github.com/warashi/configurations/.git")))
  ;; worktree から見た common dir は main の .git を指すので、その親が repo。
  (should (equal "configurations"
                 (warashi-git-wit--repository-name-in
                  "/home/me/ghq/github.com/warashi/configurations/.git/")))
  ;; bare repo では common dir 自体が repo なので、親ではなく自分の名前を使う。
  (should (equal "configurations"
                 (warashi-git-wit--repository-name-in
                  "/home/me/mirrors/configurations.git")))
  (should (equal "configurations"
                 (warashi-git-wit--repository-name-in
                  "/home/me/mirrors/configurations")))
  ;; git を呼べなかったときは repository 名無しに落ちる。
  (should-not (warashi-git-wit--repository-name-in nil))
  (should-not (warashi-git-wit--repository-name-in ""))
  (should-not (warashi-git-wit--repository-name-in "/")))

(ert-deftest warashi-git-wit-test-project-name-uses-memo ()
  "memo 付きの worktree の project 名は <repo> / <memo> (wit) になる。"
  (warashi-git-wit-test--with-worktrees warashi-git-wit-test--worktrees
    (should (equal "repo / nskk の remap を直す (wit)"
                   (project-name '(vc Git "/ssh:host:/home/me/wt/a1b2/"))))
    ;; リモートでは接続先で git-wit を走らせ、パスはローカル部分で突き合わせる。
    (should (equal '("/ssh:host:/home/me/wt/a1b2/")
                   warashi-git-wit-test--list-calls))
    ;; memo の無い worktree と管理外の project は変えない。
    (should (equal "c3d4" (project-name '(vc Git "/ssh:host:/home/me/wt/c3d4/"))))
    (should (equal "other" (project-name '(vc Git "/ssh:host:/home/me/src/other/"))))))

(ert-deftest warashi-git-wit-test-project-name-without-repository ()
  "repository 名が取れないときは memo と種類だけを使う。"
  (warashi-git-wit-test--with-worktrees warashi-git-wit-test--worktrees
    (cl-letf (((symbol-function 'warashi-git-wit--repository-name)
               (lambda (_directory) nil)))
      (should (equal "nskk の remap を直す (wit)"
                     (project-name '(vc Git "/ssh:host:/home/me/wt/a1b2/")))))))

(ert-deftest warashi-git-wit-test-project-name-cached ()
  "同じ project では git-wit を一度しか呼ばない。
agent-shell の header は再描画のたびに project 名を引くので、都度 process を
起こさない。"
  (warashi-git-wit-test--with-worktrees warashi-git-wit-test--worktrees
    (project-name '(vc Git "/ssh:host:/home/me/wt/a1b2/"))
    (project-name '(vc Git "/ssh:host:/home/me/wt/a1b2/"))
    ;; memo が無かった project も引き直さない。
    (project-name '(vc Git "/ssh:host:/home/me/wt/c3d4/"))
    (project-name '(vc Git "/ssh:host:/home/me/wt/c3d4/"))
    (should (equal 2 (length warashi-git-wit-test--list-calls)))))

(provide 'warashi-git-wit-test)
;;; warashi-git-wit-test.el ends here

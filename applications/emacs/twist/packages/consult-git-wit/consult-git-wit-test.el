;;; consult-git-wit-test.el --- Tests for consult-git-wit -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l consult-git-wit-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

;; The development shell ships a bare Emacs without consult, so stub
;; the handful of definitions consult-git-wit uses when consult itself
;; is not installed.
(unless (require 'consult nil t)
  (defconst consult--tofu-char #x200000)
  (defun consult--tofu-encode (n)
    (char-to-string (+ consult--tofu-char n)))
  (defun consult--lookup-member (selected candidates &rest _)
    (car (member selected candidates)))
  (defun consult--read (&rest _))
  (defun consult-find (&optional _dir _initial))
  (provide 'consult))

(require 'consult-git-wit)

(defconst consult-git-wit-test--ls-json
  (concat
   "[{\"id\":\"019f73e7-5d4a-7e9d-aa93-cb5bcad4aa77\","
   "\"created_at\":\"2026-07-18T06:26:10Z\","
   "\"path\":\"/tmp/wit/019f73e7\","
   "\"memo\":\"テスト用メモ\","
   "\"branch\":null,\"head\":\"aa9a1c0\",\"pr_number\":null,"
   "\"state\":\"Merged\",\"integrated\":true},"
   "{\"id\":\"019f73e8-0000-7000-8000-000000000000\","
   "\"created_at\":\"2026-07-18T07:00:00Z\","
   "\"path\":\"/tmp/wit/019f73e8\","
   "\"memo\":\"作業中\","
   "\"branch\":\"feature/x\",\"head\":\"bb00000\",\"pr_number\":42,"
   "\"state\":\"Active\",\"integrated\":false}]")
  "Fixture mirroring the output of `git-wit ls --json'.")

(defmacro consult-git-wit-test--with-ls (output status &rest body)
  "Run BODY with `call-process' stubbed to insert OUTPUT and return STATUS."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'call-process)
              (lambda (_program _infile _destination _display &rest _args)
                (insert ,output)
                ,status)))
     ,@body))

(ert-deftest consult-git-wit-test-list-parses-json ()
  "It returns one alist per worktree with the fields of the JSON output."
  (consult-git-wit-test--with-ls consult-git-wit-test--ls-json 0
    (let ((worktrees (consult-git-wit--list)))
      (should (= (length worktrees) 2))
      (let-alist (car worktrees)
        (should (equal .id "019f73e7-5d4a-7e9d-aa93-cb5bcad4aa77"))
        (should (equal .memo "テスト用メモ"))
        (should (equal .path "/tmp/wit/019f73e7"))
        (should-not .branch)
        (should (equal .state "Merged"))))))

(ert-deftest consult-git-wit-test-list-signals-on-failure ()
  "It signals an error including the process output when git-wit fails."
  (consult-git-wit-test--with-ls "fatal: not a git repository" 128
    (let ((err (should-error (consult-git-wit--list))))
      (should (string-match-p "not a git repository" (cadr err))))))

(ert-deftest consult-git-wit-test-candidate-displays-memo ()
  "It uses the memo as candidate text and stores the worktree in a property."
  (let* ((worktree '((id . "id-1") (memo . "作業中") (path . "/tmp/w")))
         (candidate (consult-git-wit--candidate worktree 0)))
    (should (string-prefix-p "作業中" candidate))
    (should (equal (consult-git-wit--worktree candidate) worktree))))

(ert-deftest consult-git-wit-test-candidate-falls-back-to-id ()
  "It falls back to the ID when the memo is empty."
  (let ((candidate (consult-git-wit--candidate '((id . "id-1") (memo . "")) 0)))
    (should (string-prefix-p "id-1" candidate))))

(ert-deftest consult-git-wit-test-candidates-with-same-memo-are-distinct ()
  "It keeps worktrees sharing a memo as distinct candidates."
  (let ((a (consult-git-wit--candidate '((id . "id-1") (memo . "fix")) 0))
        (b (consult-git-wit--candidate '((id . "id-2") (memo . "fix")) 1)))
    (should-not (equal a b))))

(ert-deftest consult-git-wit-test-annotate-shows-branch-state-and-id ()
  "It annotates candidates with branch, state and ID."
  (let* ((worktree '((id . "id-1") (memo . "m") (branch . "feature/x") (state . "Active")))
         (annotation (consult-git-wit--annotate
                      (consult-git-wit--candidate worktree 0))))
    (should (string-match-p "feature/x" annotation))
    (should (string-match-p "Active" annotation))
    (should (string-match-p "id-1" annotation))))

(ert-deftest consult-git-wit-test-annotate-detached-branch ()
  "It shows \"detached\" when the worktree has no branch."
  (let ((annotation (consult-git-wit--annotate
                     (consult-git-wit--candidate '((id . "id-1") (memo . "m")) 0))))
    (should (string-match-p "detached" annotation))))

(ert-deftest consult-git-wit-test-group-returns-state ()
  "It groups candidates by worktree state."
  (let ((candidate (consult-git-wit--candidate '((id . "id-1") (memo . "m") (state . "Active")) 0)))
    (should (equal (consult-git-wit--group candidate nil) "Active"))
    (should (equal (consult-git-wit--group candidate t) candidate))))

(ert-deftest consult-git-wit-test-find-runs-consult-find-in-selected-path ()
  "It runs `consult-find' in the directory of the selected worktree."
  (let (found-dir found-initial)
    (cl-letf (((symbol-function 'consult-git-wit--list)
               (lambda () '(((id . "id-1") (memo . "m") (path . "/tmp/wit/id-1")))))
              ((symbol-function 'consult--read)
               (lambda (candidates &rest _) (car candidates)))
              ((symbol-function 'consult-find)
               (lambda (&optional dir initial)
                 (setq found-dir dir found-initial initial))))
      (consult-git-wit-find "query")
      (should (equal found-dir "/tmp/wit/id-1/"))
      (should (equal found-initial "query")))))

(ert-deftest consult-git-wit-test-find-errors-when-no-worktrees ()
  "It signals a user error when there are no managed worktrees."
  (consult-git-wit-test--with-ls "[]" 0
    (should-error (consult-git-wit-find) :type 'user-error)))

(provide 'consult-git-wit-test)
;;; consult-git-wit-test.el ends here

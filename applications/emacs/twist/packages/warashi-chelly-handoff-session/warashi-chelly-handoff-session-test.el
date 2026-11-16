;;; warashi-chelly-handoff-session-test.el --- 横断セッションの一括作成のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-chelly-handoff-session-test.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; git-wit・chelly-handoff・agentel はそれぞれの単位の公開関数で差し替え、
;; ghq は exec-path の先頭に置いた偽の実行ファイルで差し替える。

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'warashi-chelly-handoff-session)

(defvar warashi-chelly-handoff-session-test--calls nil
  "差し替えた関数の呼び出し。(name . args) を積む。")

(defvar warashi-chelly-handoff-session-test--available t
  "`warashi-chelly-workspace-available-p' が返す値。")

(defvar warashi-chelly-handoff-session-test--clones nil
  "repository ごとの既存 clone。(REPOSITORY . ((NAME . DIRECTORY)...)) の一覧。")

(defvar warashi-chelly-handoff-session-test--failing nil
  "create が失敗する repository。")

(defvar warashi-chelly-handoff-session-test--collectable '("fix")
  "作った後に集められる handoff 名。")

(defmacro warashi-chelly-handoff-session-test--with-sources (&rest body)
  "git-wit・chelly-handoff・agentel を固定して BODY を実行する。"
  (declare (indent 0))
  `(let ((warashi-chelly-handoff-session-test--calls nil))
     (cl-letf (((symbol-function 'warashi-chelly-workspace-available-p)
                (lambda () warashi-chelly-handoff-session-test--available))
               ((symbol-function 'warashi-chelly-workspace-list)
                (lambda (repository)
                  (cdr (assoc repository warashi-chelly-handoff-session-test--clones))))
               ((symbol-function 'warashi-git-wit-add)
                (lambda (repository memo)
                  (push (list 'git-wit-add repository memo)
                        warashi-chelly-handoff-session-test--calls)
                  (concat repository "wt")))
               ((symbol-function 'warashi-chelly-workspace-create)
                (lambda (repository name)
                  (push (list 'chelly-create repository name)
                        warashi-chelly-handoff-session-test--calls)
                  (when (member repository warashi-chelly-handoff-session-test--failing)
                    (user-error "create failed"))
                  (format "/srv/chelly-workspaces/%s/" name)))
               ((symbol-function 'warashi-agentel-handoff-candidates)
                (lambda ()
                  (mapcar (lambda (name) (cons name "github.com/acme/lib"))
                          warashi-chelly-handoff-session-test--collectable)))
               ((symbol-function 'warashi-agentel-handoff)
                (lambda (name command)
                  (push (list 'handoff name command)
                        warashi-chelly-handoff-session-test--calls))))
       ,@body)))

(defun warashi-chelly-handoff-session-test--calls ()
  "呼び出しを起きた順で返す。"
  (reverse warashi-chelly-handoff-session-test--calls))

(ert-deftest warashi-chelly-handoff-session-test-creates-in-each-repository-and-starts ()
  "選んだ repository それぞれの HEAD から同じ名前の clone を作り、その名前で起動する。"
  (warashi-chelly-handoff-session-test--with-sources
    (warashi-chelly-handoff-session "fix" '("/home/me/ghq/app/" "/home/me/ghq/lib/")
                                    nil 'claude)
    (should (equal '((chelly-create "/home/me/ghq/app/" "fix")
                     (chelly-create "/home/me/ghq/lib/" "fix")
                     (handoff "fix" claude))
                   (warashi-chelly-handoff-session-test--calls)))))

(ert-deftest warashi-chelly-handoff-session-test-worktree-is-the-base ()
  "worktree を作るときは、handoff 名を memo にした worktree から clone を作る。"
  (warashi-chelly-handoff-session-test--with-sources
    (warashi-chelly-handoff-session "fix" '("/home/me/ghq/app/") t 'claude)
    (should (equal '((git-wit-add "/home/me/ghq/app/" "fix")
                     (chelly-create "/home/me/ghq/app/wt/" "fix")
                     (handoff "fix" claude))
                   (warashi-chelly-handoff-session-test--calls)))))

(ert-deftest warashi-chelly-handoff-session-test-reuses-existing-clone ()
  "同じ名前の clone がある repository では、worktree も clone も作らずに起動に含める。"
  (let ((warashi-chelly-handoff-session-test--clones
         '(("/home/me/ghq/app/" ("fix" . "/srv/chelly-workspaces/app/fix/")))))
    (warashi-chelly-handoff-session-test--with-sources
      (warashi-chelly-handoff-session "fix" '("/home/me/ghq/app/" "/home/me/ghq/lib/")
                                      t 'claude)
      (should (equal '((git-wit-add "/home/me/ghq/lib/" "fix")
                       (chelly-create "/home/me/ghq/lib/wt/" "fix")
                       (handoff "fix" claude))
                     (warashi-chelly-handoff-session-test--calls))))))

(ert-deftest warashi-chelly-handoff-session-test-stops-at-failed-repository ()
  "作成に失敗したら、残りの repository に進まず起動もしない。"
  (let ((warashi-chelly-handoff-session-test--failing '("/home/me/ghq/app/")))
    (warashi-chelly-handoff-session-test--with-sources
      (should-error (warashi-chelly-handoff-session
                     "fix" '("/home/me/ghq/app/" "/home/me/ghq/lib/") nil 'claude)
                    :type 'user-error)
      (should (equal '((chelly-create "/home/me/ghq/app/" "fix"))
                     (warashi-chelly-handoff-session-test--calls))))))

(ert-deftest warashi-chelly-handoff-session-test-refuses-before-creating ()
  "名前が空、repository が無い、専用領域が無いときは、何も作らずに止める。"
  (dolist (case '(("" ("/home/me/ghq/app/") t)
                  ("fix" nil t)
                  ("fix" ("/home/me/ghq/app/") nil)))
    (let ((warashi-chelly-handoff-session-test--available (nth 2 case)))
      (warashi-chelly-handoff-session-test--with-sources
        (should-error (warashi-chelly-handoff-session (nth 0 case) (nth 1 case) t 'claude)
                      :type 'user-error)
        (should-not warashi-chelly-handoff-session-test--calls)))))

(ert-deftest warashi-chelly-handoff-session-test-refuses-name-not-collected ()
  "作った名前が起動時に集められない (main など) なら、単独起動にせず止める。"
  (let ((warashi-chelly-handoff-session-test--collectable nil))
    (warashi-chelly-handoff-session-test--with-sources
      (should-error (warashi-chelly-handoff-session "main" '("/home/me/ghq/app/")
                                                    nil 'claude)
                    :type 'user-error)
      (should-not (assq 'handoff warashi-chelly-handoff-session-test--calls)))))

(ert-deftest warashi-chelly-handoff-session-test-repositories-come-from-ghq ()
  "参加 repository の候補は ghq の一覧で、ディレクトリとして返す。"
  (let* ((bin (make-temp-file "ghq-bin-" t))
         (exec-path (cons bin exec-path)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "ghq" bin)
            (insert "#!/bin/sh\n"
                    "[ \"$*\" = 'list -p' ] || exit 1\n"
                    "printf '/home/me/ghq/app\\n/home/me/ghq/lib\\n'\n"
                    "echo notice >&2\n"))
          (set-file-modes (expand-file-name "ghq" bin) #o755)
          (should (equal '("/home/me/ghq/app/" "/home/me/ghq/lib/")
                         (warashi-chelly-handoff-session--repositories))))
      (delete-directory bin t))))

(provide 'warashi-chelly-handoff-session-test)
;;; warashi-chelly-handoff-session-test.el ends here

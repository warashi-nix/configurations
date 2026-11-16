;;; warashi-chelly-pr-review-test.el --- PR レビュー用の handoff のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-chelly-pr-review-test.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; gh は `warashi-chelly-pr-review--gh'、git-wit と chelly-handoff はそれぞれ
;; の単位の公開関数で差し替える。

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'warashi-chelly-pr-review)

(defconst warashi-chelly-pr-review-test--list-json
  "[{\"number\":12,\"title\":\"Fix login\",\"author\":{\"login\":\"alice\"},\"headRefName\":\"fix-login\",\"isDraft\":false},
    {\"number\":7,\"title\":\"WIP: docs\",\"author\":{\"login\":\"bob\"},\"headRefName\":\"main\",\"isDraft\":true}]"
  "`gh pr list --json' の出力。fork の PR は head の branch 名が base と重なりうる。")

(defvar warashi-chelly-pr-review-test--calls nil
  "差し替えた関数の呼び出し。(name . args) を積む。")

(defmacro warashi-chelly-pr-review-test--with-sources (gh &rest body)
  "gh を GH (引数を受けて出力を返す関数) に差し替え、git-wit と chelly を固定して BODY を実行する。"
  (declare (indent 1))
  `(let ((warashi-chelly-pr-review-test--calls nil))
     (cl-letf (((symbol-function 'warashi-chelly-pr-review--gh)
                (lambda (directory &rest args)
                  (push (list 'gh directory args) warashi-chelly-pr-review-test--calls)
                  (apply ,gh args)))
               ((symbol-function 'warashi-git-wit-add)
                (lambda (repository memo)
                  (push (list 'git-wit-add repository memo) warashi-chelly-pr-review-test--calls)
                  "/home/me/wt/new-id"))
               ((symbol-function 'warashi-chelly-workspace-create)
                (lambda (repository name)
                  (push (list 'chelly-create repository name) warashi-chelly-pr-review-test--calls)
                  (format "/srv/chelly-workspaces/github.com/o/r/%s/" name))))
       ,@body)))

(ert-deftest warashi-chelly-pr-review-test-candidates ()
  "PR を番号と title で並べ、author と branch、draft かどうかを補足に出す。"
  (warashi-chelly-pr-review-test--with-sources
      (lambda (&rest _) warashi-chelly-pr-review-test--list-json)
    (let ((candidates (warashi-chelly-pr-review--candidates "/home/me/repo/")))
      (should (equal '("#12 Fix login" "#7 WIP: docs") (mapcar #'car candidates)))
      (should (equal '(12 7) (mapcar (lambda (c) (plist-get (cdr c) :number)) candidates)))
      (should (equal "alice | fix-login"
                     (plist-get (cdr (nth 0 candidates)) :annotation)))
      (should (equal "bob | main | draft"
                     (plist-get (cdr (nth 1 candidates)) :annotation)))
      ;; 一覧は repository の中で引く。
      (should (equal "/home/me/repo/"
                     (nth 1 (car warashi-chelly-pr-review-test--calls)))))))

(ert-deftest warashi-chelly-pr-review-test-create ()
  "pr-番号 の worktree を作って PR を detached で checkout し、そこから同名の clone を作る。"
  (warashi-chelly-pr-review-test--with-sources (lambda (&rest _) "")
    (should (equal "/srv/chelly-workspaces/github.com/o/r/pr-12/"
                   (warashi-chelly-pr-review-create "/home/me/repo/" 12)))
    (should (equal '((git-wit-add "/home/me/repo/" "pr-12")
                     (gh "/home/me/wt/new-id/" ("pr" "checkout" "--detach" "12"))
                     (chelly-create "/home/me/wt/new-id/" "pr-12"))
                   (reverse warashi-chelly-pr-review-test--calls)))))

(ert-deftest warashi-chelly-pr-review-test-checkout-failure-keeps-worktree ()
  "checkout に失敗したら clone は作らない。worktree は残し、そこからやり直せる。"
  (warashi-chelly-pr-review-test--with-sources
      (lambda (&rest _) (user-error "gh failed"))
    (should-error (warashi-chelly-pr-review-create "/home/me/repo/" 12)
                  :type 'user-error)
    (should-not (assq 'chelly-create warashi-chelly-pr-review-test--calls))))

(ert-deftest warashi-chelly-pr-review-test-gh-reports-output-on-failure ()
  "gh が失敗したら、端末を待たずに出力を添えて user-error にする。"
  (let ((warashi-chelly-pr-review-gh-program "sh")
        (default-directory temporary-file-directory))
    ;; `warashi-chelly-pr-review--gh' は gh の引数をそのまま渡すので、sh に読ませる。
    (let ((err (should-error
                (warashi-chelly-pr-review--gh temporary-file-directory
                                              "-c" "echo no default repo >&2; exit 1")
                :type 'user-error)))
      (should (string-match-p "no default repo" (cadr err))))
    (should (equal "ok"
                   (string-trim
                    (warashi-chelly-pr-review--gh temporary-file-directory
                                                  "-c" "echo ok"))))))

(ert-deftest warashi-chelly-pr-review-test-install ()
  "Magit の @ の transient で、create の次に p として並ぶ。"
  (warashi-chelly-pr-review-install)
  (should (eq 'warashi-chelly-pr-review
              (plist-get (cdr (transient-get-suffix 'warashi-chelly-handoff "p"))
                         :command))))

(provide 'warashi-chelly-pr-review-test)
;;; warashi-chelly-pr-review-test.el ends here

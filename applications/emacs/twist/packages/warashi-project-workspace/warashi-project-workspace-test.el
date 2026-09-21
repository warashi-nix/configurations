;;; warashi-project-workspace-test.el --- 作業場所の切り替えのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-project-workspace-test.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; consult は twist の env の実物を使う。git-wit と chelly-handoff の呼び出し
;; はそれぞれの単位の公開関数で差し替える。

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'warashi-project-workspace)

(defconst warashi-project-workspace-test--repository
  "/home/me/ghq/github.com/Warashi/configurations"
  "本人の repository。consult-ghq は末尾のスラッシュ無しで渡す。")

(defconst warashi-project-workspace-test--worktrees
  '(((id . "a1b2") (memo . "nskk の remap を直す") (path . "/home/me/wt/a1b2")
     (branch . "feature/x") (state . "Active"))
    ((id . "c3d4") (memo . "") (path . "/home/me/wt/c3d4")))
  "`warashi-git-wit-list' が返す一覧。")

(defconst warashi-project-workspace-test--clones
  '(("main" . "/srv/chelly-workspaces/configurations/main/"))
  "`warashi-chelly-workspace-list' が返す一覧。")

(defvar warashi-project-workspace-test--calls nil
  "差し替えた関数の呼び出し。(name . args) を積む。")

(defmacro warashi-project-workspace-test--with-sources (&rest body)
  "git-wit と chelly の一覧・作成を固定して BODY を実行する。
作成は名前から決まるパスを返し、呼び出しを `warashi-project-workspace-test--calls' に積む。"
  (declare (indent 0))
  `(let ((warashi-project-workspace-test--calls nil))
     (cl-letf (((symbol-function 'warashi-git-wit-list)
                (lambda (repository)
                  (push (list 'git-wit-list repository) warashi-project-workspace-test--calls)
                  warashi-project-workspace-test--worktrees))
               ((symbol-function 'warashi-chelly-workspace-list)
                (lambda (repository)
                  (push (list 'chelly-list repository) warashi-project-workspace-test--calls)
                  warashi-project-workspace-test--clones))
               ((symbol-function 'warashi-git-wit-add)
                (lambda (repository memo)
                  (push (list 'git-wit-add repository memo) warashi-project-workspace-test--calls)
                  "/home/me/wt/new-id"))
               ((symbol-function 'warashi-chelly-workspace-create)
                (lambda (repository name)
                  (push (list 'chelly-create repository name) warashi-project-workspace-test--calls)
                  (format "/srv/chelly-workspaces/configurations/%s/" name))))
       ,@body)))

(defun warashi-project-workspace-test--labels (candidates)
  "CANDIDATES の表示文字列 (tofu 抜き) を返す。"
  (mapcar (lambda (candidate) (substring-no-properties candidate 0 (1- (length candidate))))
          candidates))

;;;; 候補

(ert-deftest warashi-project-workspace-test-candidates-order-and-kind ()
  "本人の checkout を先頭に、worktree、専用 clone の順で候補を作る。"
  (warashi-project-workspace-test--with-sources
    (let* ((candidates (warashi-project-workspace--candidates
                        (concat warashi-project-workspace-test--repository "/")))
           (workspaces (mapcar #'warashi-project-workspace--workspace candidates)))
      (should (equal '("configurations" "nskk の remap を直す" "c3d4" "main")
                     (warashi-project-workspace-test--labels candidates)))
      (should (equal '(repository worktree worktree chelly)
                     (mapcar (lambda (w) (plist-get w :kind)) workspaces)))
      (should (equal (list (concat warashi-project-workspace-test--repository "/")
                           "/home/me/wt/a1b2/"
                           "/home/me/wt/c3d4/"
                           "/srv/chelly-workspaces/configurations/main/")
                     (mapcar (lambda (w) (plist-get w :directory)) workspaces)))
      ;; 一覧は repository の中で引く。
      (should (member (list 'git-wit-list (concat warashi-project-workspace-test--repository "/"))
                      warashi-project-workspace-test--calls)))))

(ert-deftest warashi-project-workspace-test-candidates-same-label-are-distinct ()
  "同じ memo の worktree と同名の clone は別の候補になる。"
  (let ((warashi-project-workspace-test--worktrees
         '(((id . "id-1") (memo . "main") (path . "/home/me/wt/id-1"))
           ((id . "id-2") (memo . "main") (path . "/home/me/wt/id-2")))))
    (warashi-project-workspace-test--with-sources
      (let ((candidates (warashi-project-workspace--candidates
                         warashi-project-workspace-test--repository)))
        (should (equal 4 (length (seq-uniq candidates))))))))

(ert-deftest warashi-project-workspace-test-annotate-and-group ()
  "worktree には branch・state・id を添え、種類ごとに group する。"
  (warashi-project-workspace-test--with-sources
    (let ((candidates (warashi-project-workspace--candidates
                       warashi-project-workspace-test--repository)))
      (should-not (warashi-project-workspace--annotate (nth 0 candidates)))
      (should (string-match-p "feature/x | Active | a1b2"
                              (warashi-project-workspace--annotate (nth 1 candidates))))
      (should (string-match-p "detached | - | c3d4"
                              (warashi-project-workspace--annotate (nth 2 candidates))))
      (should (equal '("repository" "git-wit worktree" "git-wit worktree" "chelly clone")
                     (mapcar (lambda (c) (warashi-project-workspace--group c nil)) candidates)))
      (should (equal (nth 1 candidates)
                     (warashi-project-workspace--group (nth 1 candidates) t))))))

;;;; 切り替え

(defmacro warashi-project-workspace-test--with-selection (selector &rest body)
  "consult の選択を SELECTOR で決め、切り替え先を `switched' に束縛して BODY を実行する。
SELECTOR は候補リストを受け取り、候補か入力文字列を返す関数。"
  (declare (indent 1))
  `(let ((switched nil))
     (cl-letf (((symbol-function 'consult--read)
                (lambda (candidates &rest options)
                  (funcall (plist-get options :lookup)
                           (funcall ,selector candidates) candidates)))
               ((symbol-function 'project-switch-project)
                (lambda (directory) (setq switched directory))))
       ,@body)))

(ert-deftest warashi-project-workspace-test-switch-to-existing ()
  "既存の候補を選べば、その場所へ project を切り替える。作成はしない。"
  (warashi-project-workspace-test--with-sources
    (warashi-project-workspace-test--with-selection (lambda (candidates) (nth 1 candidates))
      (warashi-project-workspace-switch warashi-project-workspace-test--repository)
      (should (equal "/home/me/wt/a1b2/" switched)))
    (warashi-project-workspace-test--with-selection (lambda (candidates) (nth 3 candidates))
      (warashi-project-workspace-switch warashi-project-workspace-test--repository)
      (should (equal "/srv/chelly-workspaces/configurations/main/" switched)))
    (should-not (seq-some (lambda (call) (memq (car call) '(git-wit-add chelly-create)))
                          warashi-project-workspace-test--calls))))

(ert-deftest warashi-project-workspace-test-switch-default-is-repository ()
  "空の入力 (既定の候補) では本人の checkout へ移る。"
  (warashi-project-workspace-test--with-sources
    (cl-letf (((symbol-function 'consult--read)
               (lambda (candidates &rest options)
                 (funcall (plist-get options :lookup)
                          (plist-get options :default) candidates)))
              ((symbol-function 'project-switch-project) #'identity))
      (should (equal (concat warashi-project-workspace-test--repository "/")
                     (warashi-project-workspace-switch
                      warashi-project-workspace-test--repository))))))

(ert-deftest warashi-project-workspace-test-switch-creates-worktree ()
  "候補に無い名前を打ち worktree を選ぶと、git-wit add してそこへ移る。"
  (warashi-project-workspace-test--with-sources
    (cl-letf (((symbol-function 'warashi-chelly-workspace-available-p) (lambda () t))
              ((symbol-function 'read-multiple-choice)
               (lambda (&rest _) '(?w "git-wit worktree"))))
      (warashi-project-workspace-test--with-selection (lambda (_) "新しい作業")
        (warashi-project-workspace-switch warashi-project-workspace-test--repository)
        (should (equal "/home/me/wt/new-id/" switched))
        (should (member (list 'git-wit-add
                              (concat warashi-project-workspace-test--repository "/")
                              "新しい作業")
                        warashi-project-workspace-test--calls))))))

(ert-deftest warashi-project-workspace-test-switch-creates-chelly-clone ()
  "候補に無い名前を打ち clone を選ぶと、chelly-handoff create してそこへ移る。"
  (warashi-project-workspace-test--with-sources
    (cl-letf (((symbol-function 'warashi-chelly-workspace-available-p) (lambda () t))
              ((symbol-function 'read-multiple-choice)
               (lambda (&rest _) '(?c "chelly clone"))))
      (warashi-project-workspace-test--with-selection (lambda (_) "feature-x")
        (warashi-project-workspace-switch warashi-project-workspace-test--repository)
        (should (equal "/srv/chelly-workspaces/configurations/feature-x/" switched))
        (should (member (list 'chelly-create
                              (concat warashi-project-workspace-test--repository "/")
                              "feature-x")
                        warashi-project-workspace-test--calls))))))

(ert-deftest warashi-project-workspace-test-switch-skips-kind-prompt-without-handoff ()
  "専用 clone を作れないホストでは種類を聞かずに worktree を作る。"
  (warashi-project-workspace-test--with-sources
    (cl-letf (((symbol-function 'warashi-chelly-workspace-available-p) (lambda () nil))
              ((symbol-function 'read-multiple-choice)
               (lambda (&rest _) (ert-fail "kind was asked"))))
      (warashi-project-workspace-test--with-selection (lambda (_) "feature-x")
        (warashi-project-workspace-switch warashi-project-workspace-test--repository)
        (should (equal "/home/me/wt/new-id/" switched))))))

(ert-deftest warashi-project-workspace-test-switch-rejects-blank-input ()
  "空白だけの入力は作らずに拒否する。"
  (warashi-project-workspace-test--with-sources
    (warashi-project-workspace-test--with-selection (lambda (_) "  ")
      (should-error (warashi-project-workspace-switch warashi-project-workspace-test--repository)
                    :type 'user-error)
      (should-not switched))))

(provide 'warashi-project-workspace-test)
;;; warashi-project-workspace-test.el ends here

;;; consult-git-wit-contract-test.el --- 上流 consult / project との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; consult-git-wit が consult と project.el に対して前提にしている呼び出し
;; 形を、スタブを一切置かずに実物へ突き当てて検証する。
;;
;; 単体テスト (consult-git-wit-test.el) は consult が無い環境でも走るよう
;; consult--read などを自前で定義し直し、さらに cl-letf で差し替える。その
;; ため上流がそれらを改名・削除・仕様変更しても緑のまま通る。
;;
;; twist の env でのみ成立する。素の Emacs には consult が無いため、
;; just test-emacs の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'find-func)
(require 'consult)
(require 'project)
(require 'consult-git-wit)

(defun consult-git-wit-contract-test--keywords (fn)
  "FN の定義をソースから読み、`&key' に並ぶキーワードの一覧を返す。
バイトコンパイル後は cl-defun のキーワードが (&rest rest) に潰れ、
`func-arity' からは改名も削除も見えない。"
  (let ((loc (find-function-noselect fn t)))
    (with-current-buffer (car loc)
      (goto-char (cdr loc))
      (let* ((arglist (nth 2 (read (current-buffer))))
             (tail (cdr (memq '&key arglist))))
        (mapcar (lambda (arg) (intern (format ":%s" (if (consp arg) (car arg) arg))))
                (seq-take-while (lambda (arg) (not (memq arg '(&rest &optional &aux))))
                                tail))))))

;;;; 候補の読み取り

(ert-deftest consult-git-wit-contract-test-read-keywords ()
  "`consult--read' が候補の読み取りに使うキーワードを受ける。"
  (let ((keywords (consult-git-wit-contract-test--keywords 'consult--read)))
    (dolist (keyword '(:prompt :category :require-match :sort :history
                       :annotate :group :lookup))
      (should (memq keyword keywords)))))

(ert-deftest consult-git-wit-contract-test-lookup-member ()
  "`consult--lookup-member' が選択された候補そのものを返す。
:lookup に渡して worktree の text property ごと受け取るので、equal な別
オブジェクトを返されると property が落ちる。"
  (let* ((candidate (propertize "x" 'consult-git-wit--worktree '((id . "1"))))
         (selected (consult--lookup-member "x" (list candidate))))
    (should (eq candidate selected))))

;;;; 候補の一意化

(ert-deftest consult-git-wit-contract-test-tofu-encode ()
  "`consult--tofu-encode' が index ごとに異なる 1 文字を返す。
memo が重なる worktree を別候補として残すために使っている。"
  (should (equal '(1 . 1) (func-arity 'consult--tofu-encode)))
  (should (= 1 (length (consult--tofu-encode 0))))
  (should-not (equal (consult--tofu-encode 0) (consult--tofu-encode 1))))

;;;; 選択後の遷移

(ert-deftest consult-git-wit-contract-test-consult-find ()
  "`consult-find' をディレクトリと初期入力で呼べる。"
  (should (equal '(0 . 2) (func-arity 'consult-find))))

(ert-deftest consult-git-wit-contract-test-project ()
  "project.el 側の切り替えと root 解決の口が変わっていない。"
  (should (boundp 'project-current-directory-override))
  (should (equal '(1 . 1) (func-arity 'project-switch-project)))
  (should (equal '(0 . 2) (func-arity 'project-current)))
  (should (fboundp 'project-root)))

(provide 'consult-git-wit-contract-test)
;;; consult-git-wit-contract-test.el ends here

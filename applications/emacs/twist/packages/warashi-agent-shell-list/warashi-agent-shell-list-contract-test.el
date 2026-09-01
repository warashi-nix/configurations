;;; warashi-agent-shell-list-contract-test.el --- 上流 agent-shell との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-agent-shell-list が agent-shell に対して前提にしている呼び出し
;; 形を、スタブを一切置かずに実物へ突き当てて検証する。
;;
;; 単体テスト (warashi-agent-shell-list-test.el) は agent-shell-buffers や
;; agent-shell-status を cl-letf で差し替えるので、上流がそれらを改名・削
;; 除・仕様変更しても緑のまま通る。
;;
;; twist の env でのみ成立する。素の Emacs には agent-shell が無いため、
;; just test-emacs の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'find-func)
(require 'agent-shell)
(require 'agent-shell-viewport)
(require 'warashi-agent-shell-list)

(defun warashi-agent-shell-list-contract-test--keywords (fn)
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

;;;; shell の一覧と状態

(ert-deftest warashi-agent-shell-list-contract-test-buffers ()
  "`agent-shell-buffers' を引数なしで呼べる。"
  (should (equal '(0 . 0) (func-arity 'agent-shell-buffers))))

(ert-deftest warashi-agent-shell-list-contract-test-status-keyword ()
  "`agent-shell-status' が :shell-buffer を受ける。"
  (should (memq :shell-buffer
                (warashi-agent-shell-list-contract-test--keywords 'agent-shell-status))))

(ert-deftest warashi-agent-shell-list-contract-test-state-is-buffer-local-variable ()
  "`agent-shell--state' を `buffer-local-value' で引ける変数として持つ。
中身が (:agent-config (:buffer-name ...)) や (:session (:title ...)) を引け
る形かまでは見ない。state を組むには session を確立した shell が要り、バッ
チでは起こせないため。スタブを置いて形だけ真似ると、このテストが塞ごうと
している穴をそのまま作り直すことになる。"
  (should (boundp 'agent-shell--state))
  (should (local-variable-if-set-p 'agent-shell--state)))

(ert-deftest warashi-agent-shell-list-contract-test-buffer-name-prefix ()
  "`agent-shell--buffer-name-prefix' を agent 名 1 つで呼べる。"
  (should (equal '(1 . 1) (func-arity 'agent-shell--buffer-name-prefix))))

;;;; 表示

(ert-deftest warashi-agent-shell-list-contract-test-faces ()
  "一覧の色付けに使う face が実在する。"
  (dolist (face '(agent-shell-error
                  agent-shell-warning
                  agent-shell-buffer-name
                  agent-shell-session-title))
    (should (facep face))))

;;;; viewport への切り替え

(ert-deftest warashi-agent-shell-list-contract-test-viewport ()
  "viewport と shell buffer を相互に辿れる。"
  (should (boundp 'agent-shell-prefer-viewport-interaction))
  (should (memq :shell-buffer
                (warashi-agent-shell-list-contract-test--keywords
                 'agent-shell-viewport--buffer)))
  (should (memq :existing-only
                (warashi-agent-shell-list-contract-test--keywords
                 'agent-shell-viewport--buffer)))
  (should (equal '(0 . 1) (func-arity 'agent-shell-viewport--shell-buffer))))

(ert-deftest warashi-agent-shell-list-contract-test-modes ()
  "`derived-mode-p' で見分ける mode が実在する。"
  (dolist (mode '(agent-shell-mode
                  agent-shell-viewport-view-mode
                  agent-shell-viewport-edit-mode))
    (should (fboundp mode)))
  (should (boundp 'agent-shell-mode-hook)))

(provide 'warashi-agent-shell-list-contract-test)
;;; warashi-agent-shell-list-contract-test.el ends here

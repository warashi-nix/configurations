;;; warashi-agent-shell-contract-test.el --- 上流 agent-shell との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-agent-shell が agent-shell に対して前提にしている呼び出し形を、
;; スタブを一切置かずに実物へ突き当てて検証する。
;;
;; 単体テスト (warashi-agent-shell-test.el) は agent-shell--state などを
;; cl-letf で差し替えるので、上流がそれらを改名・削除・仕様変更しても緑の
;; まま通る。nskk / epkgs の自動更新 PR で壊れたことに気付ける層がここ。
;;
;; twist の env でのみ成立する。素の Emacs には agent-shell が無いため、
;; just test-emacs (ファイル名が <pkg>-test.el に完全一致するものだけを
;; 拾う) の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'find-func)
(require 'agent-shell)
(require 'agent-shell-anthropic)
(require 'agent-shell-pi)
(require 'warashi-agent-shell)

(defun warashi-agent-shell-contract-test--keywords (fn)
  "FN の定義をソースから読み、`&key' に並ぶキーワードの一覧を返す。
バイトコンパイル後の `func-arity' や `help-function-arglist' は cl-defun の
キーワードを (&rest rest) に潰してしまい、キーワードの改名・削除を検出で
きない。実際に呼んで確かめる手もあるが、`agent-shell--start' のように呼
ぶと外部プロセスを起こす関数が対象に含まれるため採らない。"
  (let ((loc (find-function-noselect fn t)))
    (with-current-buffer (car loc)
      (goto-char (cdr loc))
      (let* ((arglist (nth 2 (read (current-buffer))))
             (tail (cdr (memq '&key arglist))))
        (mapcar (lambda (arg) (intern (format ":%s" (if (consp arg) (car arg) arg))))
                (seq-take-while (lambda (arg) (not (memq arg '(&rest &optional &aux))))
                                tail))))))

;;;; 打鍵の横取り

(ert-deftest warashi-agent-shell-contract-test-typing-at-prompt-p ()
  "`agent-shell--typing-at-prompt-p' を引数なしで呼べる。"
  (should (fboundp 'agent-shell--typing-at-prompt-p))
  (should (equal '(0 . 0) (func-arity 'agent-shell--typing-at-prompt-p))))

(ert-deftest warashi-agent-shell-contract-test-self-insert-commands-exist ()
  "advice を張る agent-shell のコマンドが実在する。"
  (dolist (command warashi-agent-shell-self-insert-commands)
    (should (fboundp command))))

;;;; shell の起動

(ert-deftest warashi-agent-shell-contract-test-start-keywords ()
  "`agent-shell--start' が起動に使うキーワードを受ける。"
  (let ((keywords (warashi-agent-shell-contract-test--keywords 'agent-shell--start)))
    (dolist (keyword '(:config :new-session :session-strategy :no-focus))
      (should (memq keyword keywords)))))

(ert-deftest warashi-agent-shell-contract-test-agent-configs ()
  "agent config が :default-model-id を差し替えられる alist で返る。"
  (dolist (make '(agent-shell-anthropic-make-claude-code-config
                  agent-shell-pi-make-agent-config))
    (should (equal '(0 . 0) (func-arity make)))
    (should (assq :default-model-id (funcall make)))))

;;;; thought level の適用

(ert-deftest warashi-agent-shell-contract-test-state-is-function-and-variable ()
  "`agent-shell--state' を引数なしの関数としても buffer-local 変数としても引ける。
warashi-agent-shell は関数として、warashi-agent-shell-list は
`buffer-local-value' で変数として読む。"
  (should (equal '(0 . 0) (func-arity 'agent-shell--state)))
  (should (boundp 'agent-shell--state)))

(ert-deftest warashi-agent-shell-contract-test-subscribe-to-keywords ()
  "`agent-shell-subscribe-to' が購読に使うキーワードを受ける。"
  (let ((keywords (warashi-agent-shell-contract-test--keywords 'agent-shell-subscribe-to)))
    (dolist (keyword '(:shell-buffer :event :on-event))
      (should (memq keyword keywords)))))

(ert-deftest warashi-agent-shell-contract-test-set-thought-level-keywords ()
  "`agent-shell--config-option-set-thought-level-id' が設定に使うキーワードを受ける。"
  (let ((keywords (warashi-agent-shell-contract-test--keywords
                   'agent-shell--config-option-set-thought-level-id)))
    (dolist (keyword '(:thought-level-id :on-failure))
      (should (memq keyword keywords)))))

;;;; buffer 名

(ert-deftest warashi-agent-shell-contract-test-buffer-name-prefix ()
  "`agent-shell--buffer-name-prefix' を agent 名 1 つで呼べる。"
  (should (equal '(1 . 1) (func-arity 'agent-shell--buffer-name-prefix))))

(provide 'warashi-agent-shell-contract-test)
;;; warashi-agent-shell-contract-test.el ends here

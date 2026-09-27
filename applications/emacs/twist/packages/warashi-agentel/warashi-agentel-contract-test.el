;;; warashi-agentel-contract-test.el --- agentel との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-agentel が当てにしている agentel の振る舞いを、本物の agentel に
;; 対して公開 API だけで確かめる。
;;
;; Run with:
;;   emacs -Q --batch -L . -l warashi-agentel-contract-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'agentel)

(ert-deftest warashi-agentel-contract-test-start-with-prefix-without-display ()
  "`agentel-command-prefix' の関数は session の directory を受け取り、
`agentel-start' は :display nil で buffer を表示せずに作る。"
  (let* ((received nil)
         ;; agent を起動せずにすぐ終わらせるため。
         (agentel-command-prefix (lambda (cwd) (setq received cwd) '("true")))
         (cwd (file-name-as-directory temporary-file-directory))
         (session nil))
    (unwind-protect
        (progn
          (setq session (agentel-start :cwd cwd :display nil))
          (should (equal cwd received))
          (should (buffer-live-p (agentel-session-buffer session)))
          (should-not (get-buffer-window (agentel-session-buffer session) t)))
      (when session
        (kill-buffer (agentel-session-buffer session))))))

(ert-deftest warashi-agentel-contract-test-copilot-runs-acp ()
  "`copilot' の agent は Copilot CLI を ACP で動かす。
専用 runner の中でも同じコマンドを動かすため。"
  (should (equal '("copilot" "--acp") (alist-get 'copilot agentel-agents))))

(provide 'warashi-agentel-contract-test)
;;; warashi-agentel-contract-test.el ends here

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
         (shown nil)
         (session nil))
    (cl-letf (((symbol-function 'pop-to-buffer)
               (lambda (&rest _) (setq shown t))))
      (unwind-protect
          (progn
            (setq session (agentel-start :cwd cwd :display nil))
            (should (equal cwd received))
            (should (buffer-live-p (agentel-session-buffer session)))
            (should-not shown))
        (when session
          (kill-buffer (agentel-session-buffer session)))))))

(provide 'warashi-agentel-contract-test)
;;; warashi-agentel-contract-test.el ends here

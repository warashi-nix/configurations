;;; warashi-agentel-contract-test.el --- agentel との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-agentel が当てにしている agentel の振る舞いを、本物の agentel に
;; 対して確かめる。
;;
;; Run with:
;;   emacs -Q --batch -L . -l warashi-agentel-contract-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'agentel)

(ert-deftest warashi-agentel-contract-test-start-options ()
  "`agentel-start' は model と effort を起動時の設定として受け取る。"
  (should (equal "model" (alist-get :model agentel-config--start-options)))
  (should (equal "effort" (alist-get :effort agentel-config--start-options))))

(ert-deftest warashi-agentel-contract-test-start-without-display ()
  "`agentel-start' は :display nil で buffer を表示しない。"
  (let ((shown nil)
        (session nil))
    (cl-letf (((symbol-function 'agentel-connection-start) #'ignore)
              ((symbol-function 'pop-to-buffer)
               (lambda (&rest _) (setq shown t))))
      (unwind-protect
          (progn
            (setq session (agentel-start :cwd temporary-file-directory
                                         :display nil))
            (should (buffer-live-p (agentel-session-buffer session)))
            (should-not shown))
        (when session
          (kill-buffer (agentel-session-buffer session)))))))

(ert-deftest warashi-agentel-contract-test-command-prefix-gets-cwd ()
  "`agentel-command-prefix' の関数は session の directory を受け取る。"
  (let* ((received nil)
         (agentel-command-prefix (lambda (cwd) (setq received cwd) '("wrap")))
         (agentel-command "agent")
         (agentel-command-args nil))
    (should (equal '("wrap" "agent") (agentel--command-line "/work/")))
    (should (equal "/work/" received))))

(provide 'warashi-agentel-contract-test)
;;; warashi-agentel-contract-test.el ends here

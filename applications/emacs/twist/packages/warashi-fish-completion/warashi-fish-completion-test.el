;;; warashi-fish-completion-test.el --- fish-completion の補正のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-fish-completion-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'seq)
(require 'warashi-fish-completion)

;;;; 呼び出し

(defun warashi-fish-completion-test--live-processes ()
  "生きている `warashi-fish-completion--call' 由来のプロセス。"
  (seq-filter (lambda (process)
                (and (process-live-p process)
                     (string-prefix-p "warashi-fish-completion"
                                      (process-name process))))
              (process-list)))

(ert-deftest warashi-fish-completion-test-call-returns-stdout ()
  "標準出力だけを文字列で返し、標準エラーは捨てる。"
  (should (equal "out\n"
                 (warashi-fish-completion--call
                  "sh" "-c" "echo out; echo err >&2"))))

(ert-deftest warashi-fish-completion-test-call-is-interruptible ()
  "待っている間に外から抜けられ、抜けたらプロセスを残さない。"
  (let ((start (float-time)))
    (should (eq 'interrupted
                (with-timeout (0.2 'interrupted)
                  (warashi-fish-completion--call "sleep" "5"))))
    (should (< (- (float-time) start) 2)))
  (should-not (warashi-fish-completion-test--live-processes)))

(provide 'warashi-fish-completion-test)
;;; warashi-fish-completion-test.el ends here

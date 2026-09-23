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

;;;; 候補の使い回し

(defvar warashi-fish-completion-test--asked nil
  "stub した fish に聞いたプロンプト。新しい順。")

(defun warashi-fish-completion-test--ask (directory prompt)
  "DIRECTORY で PROMPT の候補を求める。fish は聞かれたプロンプトを返す。"
  (let ((default-directory directory))
    (warashi-fish-completion--list-completions-with-desc
     (lambda (raw-prompt)
       (push raw-prompt warashi-fish-completion-test--asked)
       (concat raw-prompt "\n"))
     prompt)))

(defmacro warashi-fish-completion-test--with-fresh-cache (&rest body)
  "何も覚えていない状態から BODY を実行する。"
  (declare (indent 0))
  `(let ((warashi-fish-completion-test--asked nil))
     (warashi-fish-completion-clear-cache)
     (unwind-protect (progn ,@body)
       (warashi-fish-completion-clear-cache))))

(ert-deftest warashi-fish-completion-test-reuses-while-token-grows ()
  "同じ引数を打ち進める間と、同じ入力で聞き直されたときは fish を呼ばない。"
  (warashi-fish-completion-test--with-fresh-cache
    (should (equal "git ch\n" (warashi-fish-completion-test--ask "/repo/" "git ch")))
    (should (equal "git ch\n" (warashi-fish-completion-test--ask "/repo/" "git che")))
    (should (equal "git ch\n" (warashi-fish-completion-test--ask "/repo/" "git checkout")))
    (should (equal "git ch\n" (warashi-fish-completion-test--ask "/repo/" "git checkout")))
    (should (equal '("git ch") warashi-fish-completion-test--asked))))

(ert-deftest warashi-fish-completion-test-asks-again-when-token-changes ()
  "次の引数に移る、打ち戻す、場所が変わると fish に聞き直す。"
  (warashi-fish-completion-test--with-fresh-cache
    (warashi-fish-completion-test--ask "/repo/" "git ch")
    (warashi-fish-completion-test--ask "/repo/" "git checkout ma")
    (warashi-fish-completion-test--ask "/repo/" "git checkout m")
    (warashi-fish-completion-test--ask "/other/" "git checkout ma")
    (should (equal '("git checkout ma" "git checkout m" "git checkout ma" "git ch")
                   warashi-fish-completion-test--asked))))

(ert-deftest warashi-fish-completion-test-asks-again-after-empty-token ()
  "空の引数で聞いた結果は、打ち始めた引数に使い回さない。
fish は引数が空だとオプションを返さず、- で始めて初めて返すため。"
  (warashi-fish-completion-test--with-fresh-cache
    (warashi-fish-completion-test--ask "/repo/" "ls ")
    (warashi-fish-completion-test--ask "/repo/" "ls --co")
    (should (equal '("ls --co" "ls ") warashi-fish-completion-test--asked))))

(ert-deftest warashi-fish-completion-test-asks-again-after-clear ()
  "覚えた結果を捨てたあとは、同じ入力でも fish に聞き直す。"
  (warashi-fish-completion-test--with-fresh-cache
    (warashi-fish-completion-test--ask "/repo/" "git ch")
    (warashi-fish-completion-clear-cache)
    (warashi-fish-completion-test--ask "/repo/" "git ch")
    (should (equal '("git ch" "git ch") warashi-fish-completion-test--asked))))

(provide 'warashi-fish-completion-test)
;;; warashi-fish-completion-test.el ends here

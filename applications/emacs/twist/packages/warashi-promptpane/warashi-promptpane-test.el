;;; warashi-promptpane-test.el --- eshell で動くエージェントへの入力欄のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-promptpane-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'eshell)
(require 'warashi-promptpane)

(defun warashi-promptpane-test--wait-for (predicate)
  "PREDICATE が non-nil を返すまで process の出力を待つ。5 秒で諦める。"
  (let ((deadline (+ (float-time) 5)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.1))))

(defun warashi-promptpane-test--read (file)
  "FILE の中身。FILE がまだなければ空文字列。"
  (with-temp-buffer
    (when (file-exists-p file)
      (insert-file-contents file))
    (buffer-string)))

(defmacro warashi-promptpane-test--with-eshell (&rest body)
  "eshell のバッファを送り先にして入力欄を開き、入力欄で BODY を評価する。
BODY の中では `target' が送り先のバッファ、`received' が前面のコマンドが受け取った
内容を書くファイル。"
  (declare (indent 0))
  `(let* ((dir (file-name-as-directory (make-temp-file "warashi-promptpane-test" t)))
          (received (expand-file-name "received" dir))
          (target (let ((default-directory dir)) (eshell t))))
     (unwind-protect
         (save-window-excursion
           (switch-to-buffer target)
           (warashi-promptpane-open)
           (unwind-protect
               (progn ,@body)
             (when-let* ((pane (warashi-promptpane--buffer target)))
               (kill-buffer pane))))
       (let ((kill-buffer-query-functions nil))
         (when (buffer-live-p target)
           (kill-buffer target)))
       (delete-directory dir t))))

(defun warashi-promptpane-test--run-in-foreground (target file)
  "TARGET の eshell で、受け取った内容を FILE に書き続けるコマンドを前面で動かす。"
  (with-current-buffer target
    (goto-char (point-max))
    (insert (format "sh -c 'exec cat > %s'" (shell-quote-argument file)))
    (eshell-send-input)
    (warashi-promptpane-test--wait-for #'eshell-head-process)))

(ert-deftest warashi-promptpane-test-open-below-target ()
  "eshell の下に入力欄を開き、eshell と同じ directory で書き始める。"
  (warashi-promptpane-test--with-eshell
    (should (eq major-mode 'warashi-promptpane-mode))
    (should (equal default-directory (buffer-local-value 'default-directory target)))
    (should (eq (window-in-direction 'above) (get-buffer-window target)))))

(ert-deftest warashi-promptpane-test-open-reuses-pane ()
  "同じ eshell から開き直すと、同じ入力欄に戻る。"
  (warashi-promptpane-test--with-eshell
    (insert "書きかけ")
    (let ((pane (current-buffer)))
      (select-window (get-buffer-window target))
      (warashi-promptpane-open)
      (should (eq (current-buffer) pane))
      (should (equal (buffer-string) "書きかけ")))))

(ert-deftest warashi-promptpane-test-open-refuses-non-eshell ()
  "eshell 以外のバッファからは開かない。"
  (with-temp-buffer
    (should-error (warashi-promptpane-open) :type 'user-error)))

(ert-deftest warashi-promptpane-test-send-delivers-and-clears ()
  "送ると書いた内容が前面のコマンドに入力として届き、入力欄は空になって残る。"
  (warashi-promptpane-test--with-eshell
    (warashi-promptpane-test--run-in-foreground target received)
    (insert "一行目\n二行目")
    (warashi-promptpane-send)
    (warashi-promptpane-test--wait-for
     (lambda () (equal (warashi-promptpane-test--read received) "一行目\n二行目\n")))
    (should (equal (warashi-promptpane-test--read received) "一行目\n二行目\n"))
    (should (equal (buffer-string) ""))
    (should (eq major-mode 'warashi-promptpane-mode))))

(ert-deftest warashi-promptpane-test-send-ignores-blank ()
  "空白しか書いていなければ送らない。"
  (warashi-promptpane-test--with-eshell
    (warashi-promptpane-test--run-in-foreground target received)
    (insert " \n")
    (warashi-promptpane-send)
    (accept-process-output nil 0.2)
    (should (equal (warashi-promptpane-test--read received) ""))))

(ert-deftest warashi-promptpane-test-send-refuses-without-foreground ()
  "前面で動いているコマンドがなければ、eshell のコマンドとして実行せず書いた内容を残す。"
  (warashi-promptpane-test--with-eshell
    (insert "echo こんにちは")
    (should-error (warashi-promptpane-send) :type 'user-error)
    (should (equal (buffer-string) "echo こんにちは"))
    (should-not (with-current-buffer target
                  (save-excursion
                    (goto-char (point-min))
                    (search-forward "こんにちは" nil t))))))

(ert-deftest warashi-promptpane-test-send-refuses-dead-target ()
  "送り先がなくなっていたら送らずに書いた内容を残す。"
  (warashi-promptpane-test--with-eshell
    (insert "こんにちは")
    (let ((kill-buffer-query-functions nil))
      (kill-buffer target))
    (should-error (warashi-promptpane-send) :type 'user-error)
    (should (equal (buffer-string) "こんにちは"))))

(ert-deftest warashi-promptpane-test-abort-discards-and-closes ()
  "中断すると書いた内容を捨てて入力欄を閉じ、eshell に戻る。"
  (warashi-promptpane-test--with-eshell
    (insert "こんにちは")
    (warashi-promptpane-abort)
    (should (eq (current-buffer) target))
    (should-not (warashi-promptpane--buffer target))))

(defun warashi-promptpane-test--send (text)
  "TEXT を書いて送ったことにする。"
  (insert text)
  (cl-letf (((symbol-function 'warashi-promptpane--deliver) #'ignore))
    (warashi-promptpane-send)))

(ert-deftest warashi-promptpane-test-history-walks-back-and-forth ()
  "M-p で前に送った内容を新しい順にたどり、M-n で書きかけまで戻る。"
  (let ((warashi-promptpane-history nil))
    (warashi-promptpane-test--with-eshell
      (warashi-promptpane-test--send "一つ目")
      (warashi-promptpane-test--send "二つ目")
      (insert "書きかけ")
      (warashi-promptpane-previous-history)
      (should (equal (buffer-string) "二つ目"))
      (warashi-promptpane-previous-history)
      (should (equal (buffer-string) "一つ目"))
      (should-error (warashi-promptpane-previous-history) :type 'user-error)
      (warashi-promptpane-next-history)
      (should (equal (buffer-string) "二つ目"))
      (warashi-promptpane-next-history)
      (should (equal (buffer-string) "書きかけ"))
      (should-error (warashi-promptpane-next-history) :type 'user-error))))

(ert-deftest warashi-promptpane-test-history-starts-over-after-send ()
  "送った後に M-p を押すと、いま送った内容から呼び戻す。"
  (let ((warashi-promptpane-history nil))
    (warashi-promptpane-test--with-eshell
      (warashi-promptpane-test--send "一つ目")
      (warashi-promptpane-test--send "二つ目")
      (warashi-promptpane-previous-history)
      (warashi-promptpane-previous-history)
      (warashi-promptpane-test--send "")
      (warashi-promptpane-previous-history)
      (should (equal (buffer-string) "一つ目"))
      (warashi-promptpane-previous-history)
      (should (equal (buffer-string) "二つ目")))))

(ert-deftest warashi-promptpane-test-history-is-shared-within-project ()
  "同じ project の中の eshell なら、別の入力欄でも履歴を共有する。"
  (let ((warashi-promptpane-history nil)
        (project (file-name-as-directory (make-temp-file "warashi-promptpane-project" t))))
    (unwind-protect
        (progn
          (make-directory (expand-file-name ".git" project))
          (make-directory (expand-file-name "sub" project))
          (warashi-promptpane-test--with-eshell
            (setq default-directory project)
            (warashi-promptpane-test--send "project で送った"))
          (warashi-promptpane-test--with-eshell
            (setq default-directory (expand-file-name "sub/" project))
            (warashi-promptpane-previous-history)
            (should (equal (buffer-string) "project で送った")))
          (warashi-promptpane-test--with-eshell
            (should-error (warashi-promptpane-previous-history) :type 'user-error)))
      (delete-directory project t))))

(ert-deftest warashi-promptpane-test-history-is-bounded-and-unique ()
  "同じ内容は最新の 1 件だけを残し、残す件数には上限がある。"
  (let ((warashi-promptpane-history nil)
        (warashi-promptpane-history-length 2))
    (warashi-promptpane-test--with-eshell
      (warashi-promptpane-test--send "一つ目")
      (warashi-promptpane-test--send "二つ目")
      (warashi-promptpane-test--send "一つ目")
      (warashi-promptpane-test--send "三つ目")
      (should (equal (mapcar #'cdr warashi-promptpane-history)
                     '(("三つ目" "一つ目")))))))

(ert-deftest warashi-promptpane-test-history-survives-restart ()
  "履歴は savehist で書き出して読み戻せる形で持つ。"
  (let ((warashi-promptpane-history nil))
    (warashi-promptpane-test--with-eshell
      (warashi-promptpane-test--send (propertize "色付き" 'face 'bold))
      (should (equal (car (read-from-string (prin1-to-string warashi-promptpane-history)))
                     warashi-promptpane-history))
      (should-not (text-properties-at 0 (cadar warashi-promptpane-history))))))

(ert-deftest warashi-promptpane-test-keys ()
  "C-c C-c で送り、C-c C-k で中断し、M-p と M-n で履歴をたどる。"
  (should (eq #'warashi-promptpane-send
              (keymap-lookup warashi-promptpane-mode-map "C-c C-c")))
  (should (eq #'warashi-promptpane-abort
              (keymap-lookup warashi-promptpane-mode-map "C-c C-k")))
  (should (eq #'warashi-promptpane-previous-history
              (keymap-lookup warashi-promptpane-mode-map "M-p")))
  (should (eq #'warashi-promptpane-next-history
              (keymap-lookup warashi-promptpane-mode-map "M-n"))))

;;; warashi-promptpane-test.el ends here

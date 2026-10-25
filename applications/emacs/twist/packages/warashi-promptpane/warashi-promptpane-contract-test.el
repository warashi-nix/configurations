;;; warashi-promptpane-contract-test.el --- spectreshell との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-promptpane が当てにしている spectreshell の振る舞いを、本物の
;; spectreshell に対して確かめる。
;;
;; Run with:
;;   emacs -Q --batch -L . -l warashi-promptpane-contract-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'eshell)
(require 'spectreshell-eshell)
(require 'warashi-promptpane)

(defun warashi-promptpane-contract-test--wait-for (predicate)
  "PREDICATE が non-nil を返すまで process の出力を待つ。5 秒で諦める。"
  (let ((deadline (+ (float-time) 5)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.1))))

(defun warashi-promptpane-contract-test--read (file)
  "FILE の中身のバイト列。FILE がまだなければ空文字列。"
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (when (file-exists-p file)
      (insert-file-contents-literally file))
    (buffer-string)))

(ert-deftest warashi-promptpane-contract-test-spectreshell-pastes-to-foreground ()
  "spectreshell-eshell-mode の eshell では、前面のコマンドに本文が paste として
まとめて届き、続けて Enter が届く。"
  (let* ((dir (file-name-as-directory (make-temp-file "warashi-promptpane-contract" t)))
         (received (expand-file-name "received" dir))
         (expected (encode-coding-string "\e[200~一行目\n二行目\e[201~\r" 'utf-8))
         (target nil))
    (unwind-protect
        (progn
          (spectreshell-eshell-mode 1)
          (setq target (let ((default-directory dir)) (eshell t)))
          (with-current-buffer target
            (goto-char (point-max))
            ;; paste が囲まれるのは端末が bracketed paste を有効にした後なので、
            ;; 有効にした後に描く目印を待つ。目印をコマンド行そのものに含めないよう
            ;; printf で組み立てる。
            (insert (format "sh -c \"stty raw -echo; printf '\\\\033[?2004h%%s%%s' rea dy; exec cat > %s\""
                            (shell-quote-argument received)))
            (eshell-send-input)
            (warashi-promptpane-contract-test--wait-for
             (lambda ()
               (save-excursion
                 (goto-char (point-min))
                 (search-forward "ready" nil t)))))
          (with-temp-buffer
            (warashi-promptpane-mode)
            (setq warashi-promptpane--target target)
            (insert "一行目\n二行目")
            (warashi-promptpane-send))
          (warashi-promptpane-contract-test--wait-for
           (lambda () (equal (warashi-promptpane-contract-test--read received) expected)))
          (should (equal (warashi-promptpane-contract-test--read received) expected)))
      (when target
        (let ((kill-buffer-query-functions nil))
          (kill-buffer target)))
      (spectreshell-eshell-mode -1)
      (delete-directory dir t))))

(ert-deftest warashi-promptpane-contract-test-spectreshell-leaves-c-c-letter ()
  "前面でジョブが動いている間も、C-c に英字を続けたキーは eshell-mode-map に届く。"
  (let* ((dir (file-name-as-directory (make-temp-file "warashi-promptpane-contract" t)))
         (marker (expand-file-name "started" dir))
         (target nil))
    (unwind-protect
        (progn
          (spectreshell-eshell-mode 1)
          (setq target (let ((default-directory dir)) (eshell t)))
          (with-current-buffer target
            (goto-char (point-max))
            (insert (format "sh -c 'touch %s; exec cat > /dev/null'" (shell-quote-argument marker)))
            (eshell-send-input)
            (warashi-promptpane-contract-test--wait-for (lambda () (file-exists-p marker)))
            (should (eshell-head-process))
            (should (bound-and-true-p spectreshell-semi-char-mode))
            (let ((eshell-mode-map (copy-keymap eshell-mode-map)))
              (keymap-set eshell-mode-map "C-c q" #'ignore)
              (use-local-map eshell-mode-map)
              (should (eq #'ignore (key-binding (kbd "C-c q")))))))
      (when target
        (let ((kill-buffer-query-functions nil))
          (kill-buffer target)))
      (spectreshell-eshell-mode -1)
      (delete-directory dir t))))

;;; warashi-promptpane-contract-test.el ends here

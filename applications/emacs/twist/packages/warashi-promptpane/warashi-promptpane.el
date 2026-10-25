;;; warashi-promptpane.el --- eshell で動くエージェントに送る文章を書く入力欄  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, terminals

;;; Commentary:

;; eshell の前面で TUI のエージェントを動かしているバッファから
;; `warashi-promptpane-open' で、その下に入力欄を開く。入力欄では入力メソッドを
;; 使って書き、`warashi-promptpane-send' で前面のコマンドへまとめて送る。
;;
;; 送るときは eshell の入力欄に書いて `eshell-send-input' を呼ぶ。
;; spectreshell-eshell-mode はこれを前面のジョブへの paste と RET に変える。

;;; Code:

(declare-function eshell-head-process "esh-cmd" ())
(declare-function eshell-send-input "esh-mode"
                  (&optional use-region queue-p no-newline))

(defgroup warashi-promptpane nil
  "eshell で動くエージェントへの入力欄。"
  :group 'convenience)

(defcustom warashi-promptpane-height 5
  "入力欄の window の高さ。"
  :type 'natnum)

(defvar-local warashi-promptpane--target nil
  "この入力欄の送り先の eshell バッファ。")

(defun warashi-promptpane--buffer (target)
  "TARGET へ送る入力欄のバッファ。なければ nil。"
  (seq-find (lambda (buffer)
              (eq (buffer-local-value 'warashi-promptpane--target buffer) target))
            (buffer-list)))

(defun warashi-promptpane--deliver (target text)
  "TEXT を TARGET の eshell の前面のコマンドへ送る。"
  (with-current-buffer target
    (unless (eshell-head-process)
      (user-error "%s の前面で動いているコマンドがない" (buffer-name target)))
    (goto-char (point-max))
    (insert text)
    (eshell-send-input)))

(defvar-keymap warashi-promptpane-mode-map
  "C-c C-c" #'warashi-promptpane-send
  "C-c C-k" #'warashi-promptpane-abort)

(define-derived-mode warashi-promptpane-mode text-mode "Promptpane"
  "eshell で動くエージェントに送る文章を書くためのモード。"
  (when default-input-method
    (activate-input-method default-input-method)))

;;;###autoload
(defun warashi-promptpane-open ()
  "今の eshell バッファを送り先にした入力欄を、その下に開く。"
  (interactive)
  (unless (derived-mode-p 'eshell-mode)
    (user-error "eshell のバッファから開く"))
  (let* ((target (current-buffer))
         (pane (or (warashi-promptpane--buffer target)
                   (let ((directory default-directory))
                     (with-current-buffer
                         (generate-new-buffer (format "*promptpane %s*" (buffer-name target)))
                       (warashi-promptpane-mode)
                       (setq default-directory directory
                             warashi-promptpane--target target)
                       (current-buffer))))))
    (select-window
     (or (get-buffer-window pane)
         (display-buffer pane `(display-buffer-below-selected
                                (window-height . ,warashi-promptpane-height)))))))

(defun warashi-promptpane-send ()
  "書いた内容を送り先へ送り、入力欄を空にする。"
  (interactive)
  (let ((target warashi-promptpane--target)
        (text (buffer-string)))
    (unless (buffer-live-p target)
      (user-error "送り先がもうない"))
    (unless (string-blank-p text)
      (warashi-promptpane--deliver target text)
      (erase-buffer))))

(defun warashi-promptpane-abort ()
  "書いた内容を捨てて入力欄を閉じ、送り先に戻る。"
  (interactive)
  (let ((target warashi-promptpane--target))
    (quit-window t)
    (when-let* ((window (and (buffer-live-p target) (get-buffer-window target))))
      (select-window window))))

(provide 'warashi-promptpane)
;;; warashi-promptpane.el ends here

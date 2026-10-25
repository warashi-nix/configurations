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

(require 'project)

(declare-function eshell-head-process "esh-cmd" ())
(declare-function eshell-send-input "esh-mode"
                  (&optional use-region queue-p no-newline))

(defgroup warashi-promptpane nil
  "eshell で動くエージェントへの入力欄。"
  :group 'convenience)

(defcustom warashi-promptpane-height 5
  "入力欄の window の高さ。"
  :type 'natnum)

(defcustom warashi-promptpane-history-length 100
  "project ごとに残す送信履歴の件数。"
  :type 'natnum)

(defvar warashi-promptpane-history nil
  "project の root と、そこで送った内容の新しい順のリストの alist。
再起動後も残すには `savehist-additional-variables' に加える。")

(defvar-local warashi-promptpane--target nil
  "この入力欄の送り先の eshell バッファ。")

(defvar-local warashi-promptpane--history-index nil
  "いま入力欄に出している履歴の位置。履歴を出していなければ nil。")

(defvar-local warashi-promptpane--draft nil
  "履歴をたどり始める前に書いていた内容。")

(defun warashi-promptpane--history-key ()
  "この入力欄の履歴を分ける key。project の外では directory そのもの。"
  (expand-file-name
   (if-let* ((project (project-current nil default-directory)))
       (project-root project)
     default-directory)))

(defun warashi-promptpane--history ()
  "この入力欄の送信履歴。"
  (alist-get (warashi-promptpane--history-key) warashi-promptpane-history
             nil nil #'equal))

(defun warashi-promptpane--add-history (text)
  "TEXT をこの入力欄の送信履歴の先頭に加える。"
  (setf (alist-get (warashi-promptpane--history-key) warashi-promptpane-history
                   nil nil #'equal)
        (take warashi-promptpane-history-length
              (cons text (delete text (warashi-promptpane--history))))))

(defun warashi-promptpane--show-history (index)
  "送信履歴の INDEX 番目を入力欄に出す。-1 なら書きかけに戻す。"
  (when (null warashi-promptpane--history-index)
    (setq warashi-promptpane--draft (buffer-string)))
  (erase-buffer)
  (insert (if (< index 0)
              warashi-promptpane--draft
            (nth index (warashi-promptpane--history))))
  (setq warashi-promptpane--history-index (and (>= index 0) index)))

(defun warashi-promptpane-previous-history ()
  "一つ前に送った内容を入力欄に出す。"
  (interactive)
  (let ((index (1+ (or warashi-promptpane--history-index -1))))
    (unless (< index (length (warashi-promptpane--history)))
      (user-error "これより前の履歴はない"))
    (warashi-promptpane--show-history index)))

(defun warashi-promptpane-next-history ()
  "一つ後に送った内容を入力欄に出す。最後は書きかけに戻す。"
  (interactive)
  (unless warashi-promptpane--history-index
    (user-error "これより後の履歴はない"))
  (warashi-promptpane--show-history (1- warashi-promptpane--history-index)))

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

(defcustom warashi-promptpane-claude-directory "~/.claude/"
  "Claude Code の利用者の設定の directory。"
  :type 'directory)

(defcustom warashi-promptpane-builtin-commands
  '("agents" "clear" "compact" "config" "context" "help" "model" "resume")
  "補完する Claude Code の組み込みのスラッシュコマンド。"
  :type '(repeat string))

(defun warashi-promptpane--claude-commands (directory)
  "Claude Code の設定の DIRECTORY にある skill とコマンドの名前。"
  (append
   (mapcar (lambda (file) (file-name-nondirectory (directory-file-name (file-name-directory file))))
           (file-expand-wildcards (expand-file-name "skills/*/SKILL.md" directory)))
   (let ((commands (expand-file-name "commands" directory)))
     (when (file-directory-p commands)
       (mapcar #'file-name-base (directory-files-recursively commands "\\.md\\'"))))))

(defun warashi-promptpane--slash-commands ()
  "この入力欄から補完するスラッシュコマンド。"
  (mapcar (lambda (name) (concat "/" name))
          (delete-dups
           (append warashi-promptpane-builtin-commands
                   (warashi-promptpane--claude-commands warashi-promptpane-claude-directory)
                   (warashi-promptpane--claude-commands
                    (expand-file-name ".claude" (warashi-promptpane--history-key)))))))

(defun warashi-promptpane-completion-at-point ()
  "先頭のスラッシュコマンドと、パスに見える語を補完する。"
  (let ((end (point))
        (start (save-excursion (skip-chars-backward "^ \t\n") (point))))
    (let ((word (buffer-substring-no-properties start end)))
      (cond
       ((and (= start (point-min)) (string-match-p "\\`/[^/]*\\'" word))
        (list start end (warashi-promptpane--slash-commands) :exclusive 'no))
       ((string-match-p "\\`[~.]\\|/" word)
        (list start end #'read-file-name-internal :exclusive 'no))))))

(defvar-keymap warashi-promptpane-mode-map
  "C-c C-c" #'warashi-promptpane-send
  "C-c C-k" #'warashi-promptpane-abort
  "M-p" #'warashi-promptpane-previous-history
  "M-n" #'warashi-promptpane-next-history)

(define-derived-mode warashi-promptpane-mode text-mode "Promptpane"
  "eshell で動くエージェントに送る文章を書くためのモード。"
  ;; text-mode が入れる ispell の補完は、エージェントへの指示の語には当たらない。
  (setq-local completion-at-point-functions (list #'warashi-promptpane-completion-at-point))
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
        (text (buffer-substring-no-properties (point-min) (point-max))))
    (unless (buffer-live-p target)
      (user-error "送り先がもうない"))
    (unless (string-blank-p text)
      (warashi-promptpane--deliver target text)
      (warashi-promptpane--add-history text)
      (erase-buffer)
      (setq warashi-promptpane--history-index nil))))

(defun warashi-promptpane-abort ()
  "書いた内容を捨てて入力欄を閉じ、送り先に戻る。"
  (interactive)
  (let ((target warashi-promptpane--target))
    (quit-window t)
    (when-let* ((window (and (buffer-live-p target) (get-buffer-window target))))
      (select-window window))))

(provide 'warashi-promptpane)
;;; warashi-promptpane.el ends here

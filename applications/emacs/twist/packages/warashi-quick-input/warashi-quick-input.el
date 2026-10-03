;;; warashi-quick-input.el --- 他のアプリへ渡す文章を書くための一時バッファ  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, i18n

;;; Commentary:

;; 外のスクリプトが作った .quick-input ファイルを emacsclient で開き、
;; ここで書いた内容をスクリプトがクリップボードへ渡す。
;;
;; `warashi-quick-input-finish' は内容を保存して emacsclient に制御を返し、
;; `warashi-quick-input-abort' はファイルを空にして返す。
;; クリップボードへ入れるのを Emacs ではなくスクリプトにするのは、daemon が
;; 最後のフレームを閉じると display との接続ごと選択の所有権を失うため。

;;; Code:

(require 'server)

(defun warashi-quick-input-finish ()
  "書いた内容を保存して emacsclient に返す。"
  (interactive)
  (save-buffer)
  (server-edit))

(defun warashi-quick-input-abort ()
  "内容を捨て、ファイルを空にして emacsclient に返す。"
  (interactive)
  (erase-buffer)
  (save-buffer)
  (server-edit))

(defvar-keymap warashi-quick-input-mode-map
  "C-c C-c" #'warashi-quick-input-finish
  "C-c C-k" #'warashi-quick-input-abort)

;;;###autoload
(define-derived-mode warashi-quick-input-mode text-mode "Quick-Input"
  "他のアプリへ渡す文章を書くためのモード。"
  ;; 末尾に改行を足すと、貼り付け先で余計な改行になる。
  (setq-local require-final-newline nil)
  (when default-input-method
    (activate-input-method default-input-method)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.quick-input\\'" . warashi-quick-input-mode))

(provide 'warashi-quick-input)
;;; warashi-quick-input.el ends here

;;; warashi-chelly-workspace.el --- 専用ユーザーの作業領域の場所と命名  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, tools

;;; Commentary:

;; chelly-handoff が置く専用 clone の場所と命名規則を、一箇所で持つ。
;; clone は <root>/<repo 名>/<handoff 名> に置かれ、repo 名は本人の
;; repository の toplevel の basename になる。
;;
;; agent-shell の専用入口や project の切り替えなど、専用 clone を扱う側は
;; ここだけを見る。root や命名が変わるときに直す場所を一つにするため。

;;; Code:

(require 'subr-x)

(defgroup warashi-chelly-workspace nil
  "専用ユーザーの作業領域。"
  :group 'tools
  :prefix "warashi-chelly-workspace-")

(defcustom warashi-chelly-workspace-root "/srv/chelly-workspaces/"
  "専用ユーザーの作業領域。NixOS の chelly-agent runner と対になる。"
  :type 'directory)

(defun warashi-chelly-workspace--root ()
  "symlink を解決した root をディレクトリ形式で返す。"
  (file-name-as-directory (file-truename warashi-chelly-workspace-root)))

(defun warashi-chelly-workspace-parse (directory)
  "ローカルの DIRECTORY が専用 clone そのものなら (REPO . NAME) を返す。
root の 1 段目は repo 名の置き場で clone ではなく、clone の下の
ディレクトリも clone ではない。それらと専用領域外では nil。"
  (when-let* (((not (file-remote-p directory)))
              (root (warashi-chelly-workspace--root))
              (directory (file-name-as-directory (file-truename directory)))
              ((string-prefix-p root directory))
              (parts (split-string (string-remove-prefix root directory) "/" t))
              ((= 2 (length parts))))
    (cons (car parts) (cadr parts))))

(provide 'warashi-chelly-workspace)
;;; warashi-chelly-workspace.el ends here

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

;;;; 本人の repository から見た clone の列挙と作成

(defcustom warashi-chelly-workspace-handoff-program "chelly-handoff"
  "chelly-handoff の実行ファイル名かパス。"
  :type 'string)

(defun warashi-chelly-workspace-available-p ()
  "このホストで専用 clone を作れるなら非 nil。"
  ;; chelly-handoff は git の設定と一緒に全ホストへ入るが、専用領域は
  ;; workbench にしか無い。実行ファイルだけで判定すると、他のホストで
  ;; 種類を聞いた末に create が失敗する。
  (and (executable-find warashi-chelly-workspace-handoff-program)
       (file-directory-p warashi-chelly-workspace-root)
       t))

(defun warashi-chelly-workspace--repository-name (repository)
  "本人の REPOSITORY に対応する専用領域の repo 名を返す。
chelly-handoff は toplevel の basename を使う。"
  (file-name-nondirectory (directory-file-name repository)))

(defun warashi-chelly-workspace-path (repository name)
  "本人の REPOSITORY の handoff NAME の clone のディレクトリを返す。"
  (file-name-as-directory
   (expand-file-name name
                     (expand-file-name
                      (warashi-chelly-workspace--repository-name repository)
                      warashi-chelly-workspace-root))))

(defun warashi-chelly-workspace-list (repository)
  "本人の REPOSITORY から作られた専用 clone を (NAME . DIRECTORY) で返す。
専用領域が無いホストでは nil。"
  (let ((parent (expand-file-name
                 (warashi-chelly-workspace--repository-name repository)
                 warashi-chelly-workspace-root)))
    (when (file-directory-p parent)
      (mapcar (lambda (name)
                (cons name (file-name-as-directory (expand-file-name name parent))))
              (seq-filter (lambda (name)
                            (and (not (string-prefix-p "." name))
                                 (file-directory-p (expand-file-name name parent))))
                          (directory-files parent))))))

(defun warashi-chelly-workspace-create (repository name)
  "本人の REPOSITORY の HEAD から handoff NAME の専用 clone を作る。
作られた clone のディレクトリを返す。失敗したら出力を buffer に出して
`user-error' を出す。"
  (when (file-remote-p repository)
    (user-error "chelly-handoff must run on the workbench host, not over TRAMP"))
  (unless (warashi-chelly-workspace-available-p)
    (user-error "%s is not installed on this host"
                warashi-chelly-workspace-handoff-program))
  (let ((buffer (get-buffer-create "*chelly-handoff*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)))
    (let* ((default-directory (file-name-as-directory repository))
           (status (call-process warashi-chelly-workspace-handoff-program
                                 nil buffer nil "create" name)))
      (unless (eql status 0)
        (display-buffer buffer)
        (user-error "%s create %s failed (%s)"
                    warashi-chelly-workspace-handoff-program name status))
      (warashi-chelly-workspace-path repository name))))

(provide 'warashi-chelly-workspace)
;;; warashi-chelly-workspace.el ends here

;;; warashi-chelly-handoff-session.el --- 複数 repo に同じ handoff 名の clone を作って横断起動する  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1") (warashi-git-wit "0.1.0") (warashi-chelly-workspace "0.1.0") (warashi-agentel "0.1.0"))
;; Keywords: convenience, vc

;;; Commentary:

;; `warashi-chelly-handoff-session' で handoff 名を一度打ち、ghq の一覧から
;; 参加する repository を選ぶと、それぞれの HEAD から同じ名前の専用 clone
;; を作り、`warashi-agentel-handoff' で横断セッションを起動する。
;;
;; worktree を作るを選ぶと、handoff 名を memo にした git-wit の worktree を
;; 作ってそこから clone を作る。成果の取り込み先を普段の checkout と分ける
;; ため。
;;
;; 同じ名前の clone がある repository では何も作らずに起動に含める。途中で
;; 失敗しても、同じ操作をやり直せば続きから進む。

;;; Code:

(require 'subr-x)
(require 'warashi-git-wit)
(require 'warashi-chelly-workspace)
(require 'warashi-agentel)

(defgroup warashi-chelly-handoff-session nil
  "複数 repository の横断セッション。"
  :group 'vc
  :prefix "warashi-chelly-handoff-session-")

(defcustom warashi-chelly-handoff-session-ghq-program "ghq"
  "ghq の実行ファイル名かパス。"
  :type 'string)

(defun warashi-chelly-handoff-session--repositories ()
  "ghq が管理する repository のディレクトリを返す。"
  (with-temp-buffer
    ;; TRAMP の buffer から呼んでもローカルの ghq に聞くよう、cwd はローカルにする。
    (let ((default-directory temporary-file-directory))
      (unless (eql 0 (call-process warashi-chelly-handoff-session-ghq-program
                                   nil '(t nil) nil "list" "-p"))
        (user-error "%s list failed" warashi-chelly-handoff-session-ghq-program)))
    (mapcar #'file-name-as-directory (split-string (buffer-string) "\n" t))))

(defun warashi-chelly-handoff-session--create (name repository worktree)
  "REPOSITORY に handoff NAME の clone が無ければ作る。
WORKTREE が非 nil なら、NAME を memo にした worktree から作る。"
  (unless (assoc name (warashi-chelly-workspace-list repository))
    (warashi-chelly-workspace-create
     (if worktree
         (file-name-as-directory (warashi-git-wit-add repository name))
       repository)
     name)))

;;;###autoload
(defun warashi-chelly-handoff-session (name repositories worktree command)
  "REPOSITORIES に handoff NAME の clone を揃え、起動コマンド COMMAND で横断起動する。
WORKTREE が非 nil なら、clone の無い repository に git-wit の worktree も作る。"
  (interactive
   (list (read-string "Handoff name: ")
         (completing-read-multiple "Repositories: "
                                   (warashi-chelly-handoff-session--repositories)
                                   nil t)
         (y-or-n-p "Create git-wit worktrees? ")
         (warashi-agentel-read-variant)))
  ;; chelly-handoff は空の名前を省略とみなし、repository ごとに branch 名で作ってしまう。
  (when (string-empty-p name)
    (user-error "Handoff name must not be empty"))
  (unless repositories
    (user-error "No repository selected"))
  (unless (warashi-chelly-workspace-available-p)
    (user-error "chelly workspaces are not available on this host"))
  (dolist (repository repositories)
    (warashi-chelly-handoff-session--create name repository worktree))
  ;; main などは起動時に集められず、黙って単独起動になる。集める規則は chelly だけが持つ。
  (unless (assoc name (warashi-agentel-handoff-candidates))
    (user-error "Handoff %s cannot be collected into a session" name))
  (warashi-agentel-handoff name command))

(provide 'warashi-chelly-handoff-session)
;;; warashi-chelly-handoff-session.el ends here

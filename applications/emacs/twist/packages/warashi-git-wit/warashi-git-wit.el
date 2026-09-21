;;; warashi-git-wit.el --- git-wit の worktree を引く・作る  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, vc

;;; Commentary:

;; git-wit <https://github.com/Warashi/git-wit> のコマンド呼び出しと出力の
;; 解釈を一箇所で持つ。agent-shell の buffer 名や project の切り替えなど、
;; worktree を扱う側はここだけを見る。
;;
;; git-wit は cwd の repository の worktree だけを扱うので、どの関数も
;; 対象の DIRECTORY を受け取り、その中で走らせる。

;;; Code:

(require 'subr-x)

(defgroup warashi-git-wit nil
  "git-wit の worktree。"
  :group 'vc
  :prefix "warashi-git-wit-")

(defcustom warashi-git-wit-program "git-wit"
  "git-wit の実行ファイル名かパス。"
  :type 'string)

(defun warashi-git-wit--parse-list (json)
  "JSON (`git-wit ls --json' の出力) を worktree の alist のリストにする。
配列でない出力や壊れた出力は git-wit の出力として扱わず nil。"
  (when-let* (((stringp json))
              (worktrees (ignore-errors
                           (json-parse-string json
                                              :object-type 'alist
                                              :null-object nil
                                              :false-object nil)))
              ((vectorp worktrees)))
    (append worktrees nil)))

(defun warashi-git-wit-list (directory)
  "DIRECTORY の repository の worktree を alist のリストで返す。
各 alist は `git-wit ls --json' の要素で、id・path・memo・branch・state
などを持つ。git-wit を呼べないときや管理外では nil。"
  ;; call-process ではなく process-file なのは、DIRECTORY がリモートのときに
  ;; 手元の git-wit を叩くと、無関係な worktree 一覧と突き合わせて別の作業の
  ;; memo を付けてしまうため。
  (with-temp-buffer
    (let* ((default-directory directory)
           (status (ignore-errors
                     (process-file warashi-git-wit-program
                                   nil t nil "ls" "--json"))))
      (when (eql status 0)
        (warashi-git-wit--parse-list (buffer-string))))))

(defun warashi-git-wit--parse-add (output)
  "OUTPUT (`git-wit add' の出力) から作られた worktree のパスを返す。
最終行が \"ID<TAB>PATH\" で、その前に git の進行表示が混ざる。"
  (when-let* ((line (seq-find (lambda (line) (not (string-empty-p line)))
                              (reverse (split-string output "\n"))))
              (fields (split-string line "\t"))
              ((= 2 (length fields))))
    (cadr fields)))

(defun warashi-git-wit-add (directory memo)
  "DIRECTORY の repository の HEAD から MEMO を付けた worktree を作る。
作られた worktree のディレクトリを返す。失敗したら出力を添えて
`user-error' を出す。"
  (with-temp-buffer
    (let* ((default-directory directory)
           (status (process-file warashi-git-wit-program
                                 nil t nil "add" memo))
           (output (buffer-string)))
      (unless (eql status 0)
        (user-error "%s add failed (%s): %s"
                    warashi-git-wit-program status (string-trim output)))
      (or (warashi-git-wit--parse-add output)
          (user-error "%s add did not report the worktree path: %s"
                      warashi-git-wit-program (string-trim output))))))

(provide 'warashi-git-wit)
;;; warashi-git-wit.el ends here

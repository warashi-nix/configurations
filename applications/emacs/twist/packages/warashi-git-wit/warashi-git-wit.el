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
;;
;; `warashi-git-wit-install-project-name' を呼ぶと、memo 付きの worktree の
;; `project-name' が "<repo> / <memo> (wit)" になる。eshell や compile の
;; buffer 名、agent-shell の表示はどれも project 名から作られるので、ここで
;; 差し替えれば全部に効く。

;;; Code:

(require 'project)
(require 'seq)
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

;;;; project 名

(defvar warashi-git-wit--project-name-cache (make-hash-table :test #'equal)
  "project root ごとに解決済みの project 名。値が nil なら差し替え無し。")

(defun warashi-git-wit--memo-in (worktrees directory)
  "WORKTREES のうち、DIRECTORY のものの memo を返す。
WORKTREES は `warashi-git-wit-list' の戻り値。DIRECTORY はリモート接頭辞を
落としたパス。memo が空か無いときは nil。"
  (when-let* (((listp worktrees))
              (target (file-name-as-directory directory))
              (found (seq-find
                      (lambda (worktree)
                        (when-let* ((path (alist-get 'path worktree)))
                          (equal target (file-name-as-directory path))))
                      worktrees))
              (memo (alist-get 'memo found))
              ((not (string-empty-p memo))))
    memo))

(defun warashi-git-wit--repository-name-in (git-common-dir)
  "GIT-COMMON-DIR から repository 名を返す。
GIT-COMMON-DIR は git rev-parse --git-common-dir の出力。"
  (when-let* (((stringp git-common-dir))
              ((not (string-empty-p git-common-dir)))
              (directory (directory-file-name git-common-dir))
              (name (file-name-nondirectory directory))
              ((not (string-empty-p name))))
    ;; worktree から見た common dir は main の .git を指すので、親が repo 名に
    ;; なる。bare repo では common dir 自体が repo なので、.git で終わるときだけ
    ;; 親に上がる。
    (if (equal name ".git")
        (warashi-git-wit--repository-name-in
         (file-name-directory directory))
      (string-remove-suffix ".git" name))))

(defun warashi-git-wit--repository-name (directory)
  "DIRECTORY の属する repository の名前を返す。"
  ;; worktree は ~/.local/share/git-wit/worktrees/<id> に置かれ、ls --json も
  ;; repository を持たないので、名前は git から取るしかない。
  (with-temp-buffer
    (let* ((default-directory directory)
           (status (ignore-errors
                     (process-file "git" nil t nil "rev-parse"
                                   "--path-format=absolute" "--git-common-dir"))))
      (when (eql status 0)
        (warashi-git-wit--repository-name-in
         (string-trim (buffer-string)))))))

(defun warashi-git-wit-project-name (directory)
  "DIRECTORY が memo 付きの worktree なら \"<repo> / <memo> (wit)\" を返す。
それ以外では nil。種類を付けるのは、同じ repo の専用 clone の handoff 名と
memo が同じでも別の名前にするため。"
  (when-let* ((memo (warashi-git-wit--memo-in (warashi-git-wit-list directory)
                                              (file-local-name directory))))
    (if-let* ((repository (warashi-git-wit--repository-name directory)))
        (format "%s / %s (wit)" repository memo)
      (format "%s (wit)" memo))))

(defun warashi-git-wit--project-name-directory (root)
  "project の ROOT を cache の鍵と git-wit の照合に使う形にする。"
  ;; リモートで `file-truename' を呼ぶと接続が起きるので、symlink の解決は
  ;; ローカルのときだけにする。git-wit の ls は symlink を解決したパスを返す。
  (file-name-as-directory
   (if (file-remote-p root)
       (expand-file-name root)
     (or (ignore-errors (file-truename root)) root))))

(defun warashi-git-wit--project-name (orig project)
  "PROJECT が memo 付きの worktree なら memo の名前を返し、それ以外は ORIG に任せる。"
  ;; worktree のディレクトリ名は ID 由来で、buffer 名に並べてもどの作業か
  ;; 読み取れない。
  (let* ((directory (warashi-git-wit--project-name-directory (project-root project)))
         (cached (gethash directory warashi-git-wit--project-name-cache 'missing)))
    ;; 引き直さないのは、agent-shell の header が再描画のたびに project 名を
    ;; 引くため。memo を書き換えたときに追随しないのは、この常時呼ばれる経路で
    ;; process を起こす頻度と釣り合わないため。
    (or (if (eq cached 'missing)
            (puthash directory
                     (warashi-git-wit-project-name directory)
                     warashi-git-wit--project-name-cache)
          cached)
        (funcall orig project))))

(defun warashi-git-wit-install-project-name ()
  "memo 付きの worktree の `project-name' を repo 名と memo にする。"
  (advice-add 'project-name :around #'warashi-git-wit--project-name))

(provide 'warashi-git-wit)
;;; warashi-git-wit.el ends here

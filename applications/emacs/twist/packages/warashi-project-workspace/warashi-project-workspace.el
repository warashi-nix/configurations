;;; warashi-project-workspace.el --- repository の作業場所を選んで切り替える  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (consult "1.0") (warashi-git-wit "0.1.0") (warashi-chelly-workspace "0.1.0"))
;; Keywords: convenience, vc

;;; Commentary:

;; repository を選んだ後に、その repository のどこで作業するかを一つの
;; prompt で選ぶ。候補は本人の checkout、git-wit の worktree、専用ユーザーの
;; clone。候補に無い名前を打てば、その名前で worktree か clone を作って
;; そこへ移る。
;;
;; `consult-ghq-switch-project-function' に `warashi-project-workspace-switch'
;; を設定すると、`project-switch-project' の repository 選択の後段がこれに
;; なる。worktree や clone を作ったかどうかを覚えていなくても、同じ操作で
;; 辿り着けるようにするため。
;;
;; git-wit の worktree は repository ごとの metadata にしか載らないので、
;; 全 repository を一つの一覧にはせず、repository を選んでから列挙する。
;;
;; `warashi-project-workspace-eshell' は、今いる checkout か git-wit の
;; worktree の repository から同じ prompt で選び、移った先の eshell を開く。
;; Magit から呼ぶための入口で、移る先が専用 clone でも同じ動作にするため、
;; 本人ユーザーでは開けない Magit ではなく eshell にしている。

;;; Code:

(require 'cl-lib)
(require 'consult)
(require 'project)
(require 'seq)
(require 'let-alist)
(require 'warashi-git-wit)
(require 'warashi-chelly-workspace)

(defvar warashi-project-workspace--history nil
  "作業場所の選択の minibuffer history。")

;;;; 候補

(defun warashi-project-workspace--candidate (label kind directory index &optional annotation)
  "LABEL を表示する候補を作る。
KIND は repository / worktree / chelly、DIRECTORY は移る先。INDEX を
埋め込むのは、同じ memo の worktree を別の候補として残すため。
ANNOTATION は候補の右に出す補足。"
  (concat (propertize label
                      'warashi-project-workspace
                      (list :kind kind
                            :directory (file-name-as-directory directory)
                            :annotation annotation))
          (consult--tofu-encode index)))

(defun warashi-project-workspace--workspace (candidate)
  "CANDIDATE に埋めた作業場所の plist を返す。新しい名前の入力なら nil。"
  (get-text-property 0 'warashi-project-workspace candidate))

(defun warashi-project-workspace--worktree-candidate (worktree index)
  "git-wit の WORKTREE (alist) を候補にする。"
  (let-alist worktree
    (warashi-project-workspace--candidate
     (if (and .memo (not (string-empty-p .memo))) .memo .id)
     'worktree .path index
     (format "%s | %s | %s" (or .branch "detached") (or .state "-") .id))))

(defun warashi-project-workspace--candidates (repository)
  "REPOSITORY の作業場所の候補を返す。先頭は本人の checkout。"
  (let ((index -1))
    (append
     (list (warashi-project-workspace--candidate
            (file-name-nondirectory (directory-file-name repository))
            'repository repository (cl-incf index)))
     (mapcar (lambda (worktree)
               (warashi-project-workspace--worktree-candidate
                worktree (cl-incf index)))
             (warashi-git-wit-list repository))
     (mapcar (pcase-lambda (`(,name . ,directory))
               (warashi-project-workspace--candidate
                name 'chelly directory (cl-incf index)))
             (warashi-chelly-workspace-list repository)))))

(defun warashi-project-workspace--annotate (candidate)
  "CANDIDATE の補足を返す。"
  (when-let* ((annotation
               (plist-get (warashi-project-workspace--workspace candidate)
                          :annotation)))
    (propertize (concat "  " annotation) 'face 'completions-annotations)))

(defun warashi-project-workspace--group (candidate transform)
  "CANDIDATE を種類で group する。TRANSFORM が非 nil なら候補自身を返す。"
  (if transform
      candidate
    (pcase (plist-get (warashi-project-workspace--workspace candidate) :kind)
      ('repository "repository")
      ('worktree "git-wit worktree")
      ('chelly "chelly clone"))))

(defun warashi-project-workspace--lookup (selected candidates &rest _)
  "SELECTED が CANDIDATES に在ればその候補、無ければ入力そのものを返す。"
  (or (car (member selected candidates)) selected))

(defun warashi-project-workspace--read (repository)
  "REPOSITORY の作業場所を読む。
既存の場所なら (:kind KIND :directory DIRECTORY ...) の plist、候補に無い
名前なら (:kind new :name NAME) を返す。"
  (let* ((candidates (warashi-project-workspace--candidates repository))
         (selected (consult--read candidates
                                  :prompt (format "Workspace (%s): "
                                                  (file-name-nondirectory
                                                   (directory-file-name repository)))
                                  :category 'warashi-project-workspace
                                  :require-match nil
                                  :sort nil
                                  :default (car candidates)
                                  :history 'warashi-project-workspace--history
                                  :annotate #'warashi-project-workspace--annotate
                                  :group #'warashi-project-workspace--group
                                  :lookup #'warashi-project-workspace--lookup)))
    (or (warashi-project-workspace--workspace selected)
        (let ((name (string-trim selected)))
          (when (string-empty-p name)
            (user-error "No workspace selected"))
          (list :kind 'new :name name)))))

;;;; 作成

(defun warashi-project-workspace--read-kind (name)
  "NAME で作る種類を聞く。専用 clone を作れないホストでは worktree に決める。"
  (if (warashi-chelly-workspace-available-p)
      (car (read-multiple-choice
            (format "Create %s as" name)
            '((?w "git-wit worktree" "本人の repository の HEAD から worktree を作る")
              (?c "chelly clone" "専用ユーザーの clone を chelly-handoff create で作る"))))
    ?w))

(defun warashi-project-workspace--create (repository name)
  "REPOSITORY に NAME の作業場所を作り、そのディレクトリを返す。"
  (file-name-as-directory
   (pcase (warashi-project-workspace--read-kind name)
     (?w (warashi-git-wit-add repository name))
     (?c (warashi-chelly-workspace-create repository name)))))

;;;; 切り替え

(defun warashi-project-workspace--select (repository)
  "REPOSITORY の作業場所を選び、そのディレクトリを返す。
候補に無い名前なら、その名前で worktree か専用 clone を作る。"
  (let* ((repository (file-name-as-directory (expand-file-name repository)))
         (workspace (warashi-project-workspace--read repository)))
    (if (eq (plist-get workspace :kind) 'new)
        (warashi-project-workspace--create repository (plist-get workspace :name))
      (plist-get workspace :directory))))

;;;###autoload
(defun warashi-project-workspace-switch (repository)
  "REPOSITORY の作業場所を選び、project として切り替える。
候補に無い名前を打てば、その名前で worktree か専用 clone を作って移る。
`consult-ghq-switch-project-function' に設定して使う。"
  (interactive (list (project-root (project-current t))))
  (project-switch-project (warashi-project-workspace--select repository)))

;;;; checkout や worktree の中から

(defun warashi-project-workspace--repository-in (git-common-dir)
  "GIT-COMMON-DIR (git rev-parse --git-common-dir の出力) から本人の checkout を返す。
bare repository のように checkout が無ければ nil。"
  (let ((directory (directory-file-name git-common-dir)))
    (when (equal ".git" (file-name-nondirectory directory))
      (file-name-directory directory))))

(defun warashi-project-workspace--repository (directory)
  "DIRECTORY の属する本人の checkout を返す。git-wit の worktree の中からでも同じ。"
  ;; worktree の toplevel は ID のディレクトリで、そこを起点にすると専用 clone
  ;; の置き場 (repo 名) も本人の checkout の候補も引けない。
  (with-temp-buffer
    (let* ((default-directory directory)
           (status (ignore-errors
                     (process-file "git" nil t nil "rev-parse"
                                   "--path-format=absolute" "--git-common-dir"))))
      (or (and (eql status 0)
               (warashi-project-workspace--repository-in (string-trim (buffer-string))))
          (user-error "Not inside a Git checkout")))))

;;;###autoload
(defun warashi-project-workspace-eshell (repository)
  "REPOSITORY の作業場所を選び、その project の eshell を開く。
対話的には、今いる checkout か git-wit の worktree の repository を使う。
候補に無い名前を打てば、その名前で worktree か専用 clone を作って移る。"
  (interactive (list (warashi-project-workspace--repository default-directory)))
  (let ((project-switch-commands #'project-eshell))
    (project-switch-project (warashi-project-workspace--select repository))))

(provide 'warashi-project-workspace)
;;; warashi-project-workspace.el ends here

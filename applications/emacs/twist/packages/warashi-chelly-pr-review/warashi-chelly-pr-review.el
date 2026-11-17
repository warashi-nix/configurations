;;; warashi-chelly-pr-review.el --- PR を選んでレビュー用の専用 clone を作る  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (transient "0.5") (warashi-chelly-workspace "0.1.0") (warashi-chelly-handoff "0.1.0"))
;; Keywords: convenience, vc

;;; Commentary:

;; `gh pr list' から PR を選び、PR の head を本人の repository に fetch
;; して、checkout せずにその commit から pr-番号 の chelly-handoff の専用
;; clone を作り、その clone へ project を切り替える。PR のコードは専用環境
;; の agent に build・test させる。
;;
;; 名前を番号から作るのは、PR の title や branch 名が他人の書いた文字列で、
;; 表示以外に使いたくないため。
;;
;; `warashi-chelly-pr-review-install' で Magit の "@" の transient に並べる。

;;; Code:

(require 'json)
(require 'project)
(require 'subr-x)
(require 'warashi-chelly-workspace)

(defgroup warashi-chelly-pr-review nil
  "PR レビュー用の専用 clone。"
  :group 'vc
  :prefix "warashi-chelly-pr-review-")

(defcustom warashi-chelly-pr-review-gh-program "gh"
  "gh の実行ファイル名かパス。"
  :type 'string)

(defcustom warashi-chelly-pr-review-limit 100
  "一覧に出す PR の最大件数。"
  :type 'integer)

(defun warashi-chelly-pr-review--run (program directory args)
  "DIRECTORY で PROGRAM を ARGS で走らせ、標準出力を返す。
失敗したら stderr と標準出力を添えて `user-error' を出す。"
  (let ((stderr (make-temp-file "warashi-chelly-pr-review")))
    (unwind-protect
        (with-temp-buffer
          (let* ((default-directory (file-name-as-directory directory))
                 ;; 既定 repo の選択などで端末の入力を待たず、失敗として返させる。
                 (process-environment (cons "GH_PROMPT_DISABLED=1" process-environment))
                 (status (apply #'process-file program nil (list t stderr) nil args))
                 (output (buffer-string)))
            (unless (eql status 0)
              (user-error "%s %s failed (%s): %s"
                          program (string-join args " ") status
                          (string-trim
                           (concat (with-temp-buffer
                                     (insert-file-contents stderr)
                                     (buffer-string))
                                   output))))
            output))
      (delete-file stderr))))

(defun warashi-chelly-pr-review--gh (directory &rest args)
  "DIRECTORY で gh を ARGS で走らせ、標準出力を返す。"
  (warashi-chelly-pr-review--run warashi-chelly-pr-review-gh-program directory args))

(defun warashi-chelly-pr-review--git (directory &rest args)
  "DIRECTORY で git を ARGS で走らせ、標準出力を返す。"
  (warashi-chelly-pr-review--run "git" directory args))

(defun warashi-chelly-pr-review--candidates (repository)
  "REPOSITORY の open な PR を (LABEL . (:number N :annotation A)) で返す。"
  (mapcar
   (lambda (pr)
     (let-alist pr
       (cons (format "#%d %s" .number .title)
             (list :number .number
                   :annotation (string-join
                                (delq nil (list .author.login .headRefName
                                                (and (eq .isDraft t) "draft")))
                                " | ")))))
   (json-parse-string
    (warashi-chelly-pr-review--gh
     repository "pr" "list"
     "--limit" (number-to-string warashi-chelly-pr-review-limit)
     "--json" "number,title,author,headRefName,isDraft")
    :object-type 'alist :array-type 'list :false-object nil)))

(defun warashi-chelly-pr-review--read (repository)
  "REPOSITORY の PR を一つ選ばせ、その番号を返す。"
  (let* ((candidates (or (warashi-chelly-pr-review--candidates repository)
                         (user-error "No open pull requests")))
         (completion-extra-properties
          (list :annotation-function
                (lambda (label)
                  (when-let* ((annotation (plist-get (cdr (assoc label candidates))
                                                     :annotation)))
                    (concat "  " annotation)))))
         (selected (completing-read "Review PR: " candidates nil t)))
    (plist-get (cdr (assoc selected candidates)) :number)))

(defun warashi-chelly-pr-review-create (repository number)
  "REPOSITORY の PR NUMBER の head からレビュー用の専用 clone を作る。
clone のディレクトリを返す。"
  (let ((name (format "pr-%d" number))
        url commit)
    (unless (warashi-chelly-workspace-available-p)
      (user-error "chelly workspaces are not available on this host"))
    (when (assoc name (warashi-chelly-workspace-list repository))
      (user-error "Handoff %s already exists" name))
    ;; fork の PR でも head は base の repository の refs/pull/番号/head にある。
    ;; PR 一覧と同じ repository から取るよう、remote ではなく gh の既定 repo の URL から引く。
    (setq url (string-trim
               (warashi-chelly-pr-review--gh repository "repo" "view" "--json" "url"
                                             "--jq" ".url"))
          commit (string-trim
                  (warashi-chelly-pr-review--gh repository "pr" "view"
                                                (number-to-string number)
                                                "--json" "headRefOid" "--jq" ".headRefOid")))
    (warashi-chelly-pr-review--git repository "fetch" "--quiet" "--no-tags" url
                                   (format "refs/pull/%d/head" number))
    (warashi-chelly-workspace-create repository name commit)))

;;;###autoload
(defun warashi-chelly-pr-review (repository)
  "REPOSITORY の PR を選び、レビュー用の専用 clone を作ってその project へ移る。
対話的には、今いる project の root を使う。"
  (interactive (list (project-root (project-current t))))
  (project-switch-project
   (warashi-chelly-pr-review-create
    repository (warashi-chelly-pr-review--read repository))))

;;;###autoload
(defun warashi-chelly-pr-review-install ()
  "Magit の \"@\" の transient に PR レビュー用の create を並べる。"
  (require 'transient)
  (require 'warashi-chelly-handoff)
  (transient-append-suffix 'warashi-chelly-handoff "c"
    '("p" "Create for PR review" warashi-chelly-pr-review)))

(provide 'warashi-chelly-pr-review)
;;; warashi-chelly-pr-review.el ends here

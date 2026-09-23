;;; warashi-chelly-handoff.el --- Magit から chelly-handoff を呼ぶ  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (magit "4.0") (transient "0.5") (warashi-chelly-workspace "0.1.0"))
;; Keywords: convenience, vc

;;; Commentary:

;; 本人の repository の Magit から、専用 clone との受け渡しを呼ぶ入口。
;; `warashi-chelly-handoff' の transient から chelly-handoff を Magit の
;; process として走らせ、終わったら Magit の buffer を refresh する。
;; fetch の後は受け取った範囲の log を開き、そのまま cherry-pick できる。
;;
;; 状態は chelly-handoff と同じく remote handoff-NAME の設定だけを読む。
;; `warashi-chelly-handoff-install' で `magit-dispatch' と Magit の
;; buffer の "@" から開けるようにする。

;;; Code:

(require 'magit)
(require 'transient)
(require 'warashi-chelly-workspace)

;;;; handoff 名

(defun warashi-chelly-handoff--parse-names (lines)
  "`git config --get-regexp' の LINES から chelly-handoff が作った handoff 名を返す。"
  (delq nil
        (mapcar (lambda (line)
                  (when (string-match "\\`remote\\.handoff-\\(.+\\)\\.chelly-base " line)
                    (match-string 1 line)))
                lines)))

(defun warashi-chelly-handoff--names ()
  "現在の repository の handoff 名を返す。"
  (warashi-chelly-handoff--parse-names
   (magit-git-lines "config" "--get-regexp" "^remote\\.handoff-.*\\.chelly-base$")))

(defun warashi-chelly-handoff--read-name (verb)
  "VERB の対象にする handoff 名を読む。一つしか無ければ聞かない。"
  (pcase (warashi-chelly-handoff--names)
    ('nil (user-error "No chelly-handoff workspace in this repository"))
    (`(,name) name)
    (names (completing-read (format "%s handoff: " verb) names nil t))))

;;;; 起動

(defun warashi-chelly-handoff--start (args &optional after)
  "本人の repository の toplevel で chelly-handoff を ARGS で起動する。
終わったら Magit の buffer を refresh し、AFTER があれば終了コードを
渡して呼ぶ。AFTER は repository の toplevel で呼ばれる。"
  (when (file-remote-p default-directory)
    (user-error "chelly-handoff must run on the local host, not over TRAMP"))
  (unless (warashi-chelly-workspace-available-p)
    (user-error "%s is not installed on this host"
                warashi-chelly-workspace-handoff-program))
  (let* ((default-directory (or (magit-toplevel)
                                (user-error "Not inside a Git repository")))
         ;; pty だと chelly-agent の stdout が端末になり、podman が --tty で
         ;; 端末を attach しようとする。パスフレーズなどの入力も要らない。
         (magit-process-connection-type nil)
         (process (apply #'magit-start-process
                         warashi-chelly-workspace-handoff-program nil args)))
    (when (and process after)
      (set-process-sentinel
       process
       (lambda (process event)
         (magit-process-sentinel process event)
         (when (memq (process-status process) '(exit signal))
           (let ((default-directory (process-get process 'default-dir)))
             (funcall after (process-exit-status process)))))))
    process))

;;;; fetch

(defun warashi-chelly-handoff--log-range (base refs)
  "BASE から、受け取った REFS の唯一の ref までの範囲を返す。
ref が一つでなければ範囲は決まらないので nil。"
  (when (and base refs (null (cdr refs)))
    (format "%s..%s" base (car refs))))

(defun warashi-chelly-handoff--after-fetch (name status)
  "handoff NAME の fetch が STATUS で終わった後に、受け取った範囲の log を開く。"
  ;; 1 は新規追跡ファイルの検査で見つかった場合で、ref は受け取り済み。
  ;; 何が引っかかったかは process buffer にしか出ないので、log と並べて見せる。
  (when (memq status '(0 1))
    (let* ((remote (concat "handoff-" name))
           (range (warashi-chelly-handoff--log-range
                   (magit-get "remote" remote "chelly-base")
                   (magit-git-lines "for-each-ref" "--format=%(refname:short)"
                                    (format "refs/remotes/%s/" remote)))))
      (when range
        (apply #'magit-log-setup-buffer (list range) (magit-log-arguments)))
      (when (eq status 1)
        (magit-process-buffer)))))

(defun warashi-chelly-handoff-fetch (name)
  "専用 clone の handoff NAME の commit を受け取り、その範囲の log を開く。"
  (interactive (list (warashi-chelly-handoff--read-name "Fetch")))
  (warashi-chelly-handoff--start
   (list "fetch" name)
   (lambda (status) (warashi-chelly-handoff--after-fetch name status))))

;;;; update

(defun warashi-chelly-handoff-update (name)
  "専用 clone の handoff NAME を本人の branch の先端に合わせ直す。"
  (interactive (list (warashi-chelly-handoff--read-name "Update")))
  (warashi-chelly-handoff--start (list "update" name)))

;;;; create と remove

(defconst warashi-chelly-handoff--name-pattern
  "\\`[A-Za-z0-9][A-Za-z0-9._-]\\{0,127\\}\\'"
  "chelly-handoff が受け付ける handoff 名。専用領域の path になる。")

(defun warashi-chelly-handoff--usable-name-p (name)
  "NAME を handoff 名に使えるなら非 nil。"
  (and name (string-match-p warashi-chelly-handoff--name-pattern name)))

(defun warashi-chelly-handoff-create (name)
  "現在の HEAD から handoff NAME の専用 clone を作る。移らずにその場に留まる。"
  (interactive
   (let* ((branch (magit-get-current-branch))
          (default (and (warashi-chelly-handoff--usable-name-p branch) branch)))
     (list (read-string (format-prompt "Create handoff" default) nil nil default))))
  (unless (warashi-chelly-handoff--usable-name-p name)
    (user-error "Handoff name must start with an ASCII letter or digit and contain only letters, digits, '.', '_' or '-'"))
  (warashi-chelly-handoff--start (list "create" name)))

(defun warashi-chelly-handoff-remove (name args)
  "handoff NAME の専用 clone と remote を消す。
ARGS に --force があれば、受け取っていない commit や未コミットの変更も捨てる。"
  (interactive (list (warashi-chelly-handoff--read-name "Remove")
                     (transient-args 'warashi-chelly-handoff)))
  (let ((force (member "--force" args)))
    (unless (y-or-n-p (format "Remove handoff %s%s? " name
                              (if force " and discard uncollected work" "")))
      (user-error "Aborted"))
    (warashi-chelly-handoff--start (append (list "remove" name) (and force '("--force"))))))

;;;; 入口

;;;###autoload (autoload 'warashi-chelly-handoff "warashi-chelly-handoff" nil t)
(transient-define-prefix warashi-chelly-handoff ()
  "専用 clone との受け渡し。"
  ["Arguments"
   ("-f" "Discard uncollected work on remove" "--force")]
  ["chelly-handoff"
   ("c" "Create" warashi-chelly-handoff-create)
   ("f" "Fetch" warashi-chelly-handoff-fetch)
   ("u" "Update" warashi-chelly-handoff-update)
   ("k" "Remove" warashi-chelly-handoff-remove)])

;;;###autoload
(defun warashi-chelly-handoff-install ()
  "`magit-dispatch' と Magit の buffer の \"@\" から handoff を開けるようにする。"
  (keymap-set magit-mode-map "@" #'warashi-chelly-handoff)
  (transient-append-suffix 'magit-dispatch "!"
    '("@" "Chelly handoff" warashi-chelly-handoff)))

(provide 'warashi-chelly-handoff)
;;; warashi-chelly-handoff.el ends here

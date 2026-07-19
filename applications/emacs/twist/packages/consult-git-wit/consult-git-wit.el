;;; consult-git-wit.el --- Consult interface for git-wit worktrees -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (consult "1.0"))
;; Keywords: convenience, vc
;; URL: https://github.com/Warashi/consult-git-wit

;;; Commentary:

;; This package provides a Consult-based interface to git-wit
;; <https://github.com/Warashi/git-wit>, a tool that manages Git
;; worktrees by stable IDs and metadata.
;;
;; `consult-git-wit-find' lets you pick a managed worktree of the
;; current repository by its memo, then runs `consult-find' inside the
;; selected worktree directory.
;;
;; `consult-git-wit-switch' picks a worktree the same way and
;; switches to it as a project via `project-switch-project'.
;;
;; `consult-git-wit-project-find' and `consult-git-wit-project-switch'
;; are variants that resolve the repository from the current project,
;; so they can be used as entries in `project-switch-commands':
;;
;;   (add-to-list 'project-switch-commands
;;                '(consult-git-wit-project-switch "git-wit worktree" ?w))

;;; Code:

(require 'consult)
(require 'project)
(require 'seq)
(require 'let-alist)

(defgroup consult-git-wit nil
  "Consult interface for git-wit managed worktrees."
  :group 'consult
  :prefix "consult-git-wit-")

(defcustom consult-git-wit-program "git-wit"
  "Name or path of the git-wit executable."
  :type 'string)

(defvar consult-git-wit--history nil
  "Minibuffer history for `consult-git-wit' worktree selection.")

(defun consult-git-wit--list ()
  "Return managed worktrees of the current repository.
Each worktree is an alist parsed from `git-wit ls --json'."
  (with-temp-buffer
    (let ((status (call-process consult-git-wit-program nil t nil "ls" "--json")))
      (unless (eql status 0)
        (error "%s ls --json failed (%s): %s"
               consult-git-wit-program status (string-trim (buffer-string)))))
    (goto-char (point-min))
    (append (json-parse-buffer :object-type 'alist
                               :null-object nil
                               :false-object nil)
            nil)))

(defun consult-git-wit--candidate (worktree index)
  "Format WORKTREE as a minibuffer completion candidate.
INDEX is encoded into the candidate so that worktrees sharing the
same memo remain distinct candidates."
  (let-alist worktree
    (concat (propertize (if (and .memo (not (string-empty-p .memo))) .memo .id)
                        'consult-git-wit--worktree worktree)
            (consult--tofu-encode index))))

(defun consult-git-wit--worktree (candidate)
  "Return the worktree alist stored in CANDIDATE."
  (get-text-property 0 'consult-git-wit--worktree candidate))

(defun consult-git-wit--annotate (candidate)
  "Return annotation with branch, state and ID for CANDIDATE."
  (let-alist (consult-git-wit--worktree candidate)
    (propertize (format "  %s | %s | %s"
                        (or .branch "detached")
                        (or .state "-")
                        .id)
                'face 'completions-annotations)))

(defun consult-git-wit--group (candidate transform)
  "Group CANDIDATE by worktree state.
If TRANSFORM is non-nil, return CANDIDATE itself."
  (if transform
      candidate
    (alist-get 'state (consult-git-wit--worktree candidate))))

(defun consult-git-wit--read-worktree ()
  "Read a managed worktree of the current repository via Consult."
  (let* ((worktrees (or (consult-git-wit--list)
                        (user-error "No git-wit managed worktrees")))
         (candidates (seq-map-indexed #'consult-git-wit--candidate worktrees))
         (selected (consult--read candidates
                                  :prompt "git-wit worktree: "
                                  :category 'consult-git-wit-worktree
                                  :require-match t
                                  :sort nil
                                  :history 'consult-git-wit--history
                                  :annotate #'consult-git-wit--annotate
                                  :group #'consult-git-wit--group
                                  :lookup #'consult--lookup-member)))
    (consult-git-wit--worktree selected)))

;;;###autoload
(defun consult-git-wit-find (&optional initial)
  "Select a git-wit managed worktree and run `consult-find' in it.
INITIAL is passed to `consult-find' as the initial input."
  (interactive)
  (let-alist (consult-git-wit--read-worktree)
    (consult-find (file-name-as-directory .path) initial)))

;;;###autoload
(defun consult-git-wit-switch ()
  "Select a git-wit managed worktree and switch to it as a project."
  (interactive)
  (let-alist (consult-git-wit--read-worktree)
    (project-switch-project (file-name-as-directory .path))))

(defun consult-git-wit--project-root ()
  "Return the root directory of the current project.
`project-current' honors `project-current-directory-override', so
callers work as members of `project-switch-commands'."
  (file-name-as-directory (project-root (project-current t))))

;;;###autoload
(defun consult-git-wit-project-find (&optional initial)
  "Run `consult-git-wit-find' on the worktrees of the current project.
INITIAL is passed to `consult-find' as the initial input.
Usable as an entry in `project-switch-commands'."
  (interactive)
  (let ((default-directory (consult-git-wit--project-root)))
    (consult-git-wit-find initial)))

;;;###autoload
(defun consult-git-wit-project-switch ()
  "Run `consult-git-wit-switch' on the worktrees of the current project.
Usable as an entry in `project-switch-commands'."
  (interactive)
  (let ((default-directory (consult-git-wit--project-root)))
    (consult-git-wit-switch)))

(provide 'consult-git-wit)
;;; consult-git-wit.el ends here

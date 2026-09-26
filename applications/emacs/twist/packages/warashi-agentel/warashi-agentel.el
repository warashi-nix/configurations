;;; warashi-agentel.el --- agentel の起動まわり  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1") (agentel "0.1.0") (warashi-chelly-workspace "0.1.0"))
;; Keywords: convenience, tools

;;; Commentary:

;; agentel に足している三つのこと。
;;
;; - model と effort を固定した Claude の起動コマンド。起動しても表示も
;;   focus もしない。
;; - `project-switch-project' のディスパッチから variant を選んで起動する。
;;   起動しても session には飛ばず、同じ project のメニューを開き直す。
;; - `warashi-chelly-workspace-root' 以下では agent を chelly-agent の専用
;;   runner で動かす。
;;
;; 利用側で `agentel-command-prefix' に `warashi-agentel-command-prefix' を
;; 設定し、専用領域の外で使う prefix を
;; `warashi-agentel-ordinary-command-prefix' に置く。起動コマンドは
;; `warashi-agentel-define-claude-variants' で作る。

;;; Code:

(require 'project)
(require 'subr-x)
(require 'warashi-chelly-workspace)
(declare-function agentel-start "agentel")
(declare-function agentel-session-buffer "agentel-session")

;;;; 専用 runner への振り分け

(defcustom warashi-agentel-ordinary-command-prefix nil
  "専用作業領域の外で agent の前に置くコマンド列。"
  :type '(repeat string)
  :group 'tools)

(defconst warashi-agentel-dedicated-command-prefix '("chelly-agent" "run" "--")
  "専用作業領域の中で agent の前に置くコマンド列。")

(defun warashi-agentel--dedicated-directory (directory)
  "DIRECTORY が専用作業領域の中なら、symlink を解決した絶対パスを返す。
専用領域に見えて実体が外にあるときは `user-error' を投げる。"
  (unless (file-remote-p directory)
    (let* ((lexical (file-name-as-directory (expand-file-name directory)))
           (lexical-root (file-name-as-directory
                          (expand-file-name warashi-chelly-workspace-root)))
           (canonical (file-name-as-directory (file-truename lexical)))
           (canonical-root (file-name-as-directory
                            (file-truename lexical-root))))
      (cond
       ((or (equal canonical canonical-root)
            (file-in-directory-p canonical canonical-root))
        canonical)
       ;; 外として扱うと、専用領域のつもりの作業が本人の credential で動く。
       ((string-prefix-p lexical-root lexical)
        (user-error "chelly-agent path escapes dedicated workspace: %s"
                    lexical))))))

(defun warashi-agentel-command-prefix (cwd)
  "CWD で agent を動かすコマンド列を返す。`agentel-command-prefix' 用。"
  ;; 起動コマンドを通らない /resume でも振り分けるため、ここでも判定する。
  (if (warashi-agentel--dedicated-directory cwd)
      warashi-agentel-dedicated-command-prefix
    warashi-agentel-ordinary-command-prefix))

;;;; 起動コマンド

(defvar warashi-agentel-variants nil
  "起動コマンドの一覧。要素は (NAME . COMMAND) で、定義順に並ぶ。")

(defun warashi-agentel-register-variant (name command)
  "NAME で選べる起動コマンド COMMAND を一覧に載せる。"
  ;; 同じ NAME を上書きするのは、init.org を評価し直すたびに候補が伸びるのを
  ;; 防ぐため。
  (if-let* ((found (assoc name warashi-agentel-variants)))
      (setcdr found command)
    (setq warashi-agentel-variants
          (append warashi-agentel-variants (list (cons name command))))))

(defun warashi-agentel--start-claude (model effort)
  "MODEL と EFFORT を指定して Claude の session を起動する。表示はしない。"
  ;; agentel は agent をローカルで動かし、cwd もそのまま渡すので、TRAMP 先の
  ;; path では agent が作業場所を見失う。
  (when (file-remote-p default-directory)
    (user-error "agentel cannot start an agent over TRAMP: %s"
                default-directory))
  (require 'agentel)
  ;; 専用領域の判定を起動前に済ませるのは、`agentel-command-prefix' で拒否
  ;; すると作りかけの session buffer が残るため。実体のパスを渡すのは、専用
  ;; runner が作業領域を実体のパスで mount するため。
  (agentel-start :cwd (or (warashi-agentel--dedicated-directory default-directory)
                          default-directory)
                 :display nil
                 :model model
                 :effort effort))

(defmacro warashi-agentel-define-claude-variants (&rest variants)
  "VARIANTS から Claude の起動コマンドを定義する。
VARIANTS の各要素は (NAME MODEL EFFORT)。NAME ごとに
`warashi-agentel-claude-NAME' と、eshell から短い名前で呼ぶための
`eshell/claude-NAME' を生成する。"
  `(progn
     ,@(mapcan
        (pcase-lambda (`(,name ,model ,effort))
          (let ((fn (intern (format "warashi-agentel-claude-%s" name)))
                (eshell-fn (intern (format "eshell/claude-%s" name))))
            (list
             `(defun ,fn ()
                ,(format "Claude を model %s / effort %s で起動する。"
                         model effort)
                (interactive)
                (warashi-agentel--start-claude ,model ,effort))
             `(defun ,eshell-fn (&rest _args)
                ,(format "eshell から `%s' を起動し、起動した buffer を示す。" fn)
                ;; session をそのまま返すと、eshell が struct を丸ごと出力する。
                (format ,(format "claude-%s: started %%s" name)
                        (buffer-name (agentel-session-buffer (,fn)))))
             `(warashi-agentel-register-variant
               ,(format "claude-%s" name) ',fn))))
        variants)))

;;;; project-switch からの起動

(defun warashi-agentel--read-variant ()
  "起動する variant のコマンドを選ばせて返す。"
  (let ((name (completing-read "Agent: "
                               (mapcar #'car warashi-agentel-variants)
                               nil t)))
    (alist-get name warashi-agentel-variants nil nil #'equal)))

(defun warashi-agentel-project-switch ()
  "variant を選んで起動し、`project-switch-project' のメニューに戻る。"
  (interactive)
  (when-let* ((command (warashi-agentel--read-variant)))
    (funcall command))
  ;; メニューを開き直すのは、`project-current-directory-override' が
  ;; ディスパッチしたコマンドの終了で消えるため。起動して戻るだけでは元の
  ;; project に居る状態になり、続けて magit を開くのに project を選び直す
  ;; ことになる。M-x から呼んだときに開かないのは、戻る先のメニューが無いため。
  (when project-current-directory-override
    (project-switch-project project-current-directory-override)))

(provide 'warashi-agentel)
;;; warashi-agentel.el ends here

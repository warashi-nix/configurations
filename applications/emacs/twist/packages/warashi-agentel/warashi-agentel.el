;;; warashi-agentel.el --- agentel の起動まわり  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1") (agentel "0.1.0") (warashi-chelly-workspace "0.1.0"))
;; Keywords: convenience, tools

;;; Commentary:

;; agentel に足している五つのこと。
;;
;; - model と effort を固定した Claude と Copilot CLI の起動コマンド。
;;   起動しても表示も focus もしない。
;; - `project-switch-project' のディスパッチから variant を選んで起動する。
;;   起動しても session には飛ばず、同じ project のメニューを開き直す。
;; - agent は `warashi-chelly-workspace-root' 以下でだけ、chelly の専用
;;   runner で動かす。
;; - Claude Code の session を project 名で登録させる。
;; - brainium の clone から、同じ handoff 名の clone を集めて起動する
;;   (`warashi-agentel-handoff')。
;;
;; 利用側で `agentel-command-prefix' に `warashi-agentel-command-prefix' を
;; 設定する。起動コマンドは
;; `warashi-agentel-define-claude-variants' と
;; `warashi-agentel-define-copilot-variants' で作る。

;;; Code:

(require 'project)
(require 'subr-x)
(require 'warashi-chelly-workspace)
(declare-function agentel-start "agentel")
(declare-function agentel-session-buffer "agentel-session")

;;;; 専用 runner への振り分け

(defconst warashi-agentel-dedicated-command-prefix '("chelly" "run" "--")
  "専用作業領域の中で agent の前に置くコマンド列。")

(defun warashi-agentel--dedicated-directory (directory)
  "DIRECTORY が専用作業領域の中なら、symlink を解決した絶対パスを返す。
専用領域の外のときは `user-error' を投げる。"
  (when (file-remote-p directory)
    (user-error "agents run only inside %s: %s"
                warashi-chelly-workspace-root directory))
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
     ((string-prefix-p lexical-root lexical)
      (user-error "chelly path escapes dedicated workspace: %s"
                  lexical))
     (t
      (user-error "agents run only inside %s: %s"
                  warashi-chelly-workspace-root lexical)))))

(defun warashi-agentel--session-name-command (options)
  "Claude Code の session を名前で登録させるコマンド列を返す。
名前は起動 option の OPTIONS の :project、無ければ :cwd の project 名。
どちらも無ければ nil。"
  ;; `agentel-environment' で渡さないのは、変数が prefix の先頭の chelly に
  ;; しか届かず、NixOS では sudo と runner が環境を捨てるため。通すには
  ;; 権限境界の許可を広げることになる。
  (when-let* ((name (or (plist-get options :project)
                        (when-let* ((project (project-current nil (plist-get options :cwd))))
                          (project-name project)))))
    (list "env" (concat "CLAUDE_CODE_SESSION_NAME=" name))))

(defun warashi-agentel-command-prefix (options)
  "起動 option の OPTIONS で agent を動かすコマンド列を返す。
:handoff があれば、その名前の clone を chelly に集めさせる。
`agentel-command-prefix' 用。"
  ;; 起動コマンドを通らない /resume でも拒否するため、ここでも判定する。
  (warashi-agentel--dedicated-directory (plist-get options :cwd))
  (append (if-let* ((handoff (plist-get options :handoff)))
              ;; chelly の入口が --handoff を run の前で受け取る。
              (append (list (car warashi-agentel-dedicated-command-prefix)
                            "--handoff" handoff)
                      (cdr warashi-agentel-dedicated-command-prefix))
            warashi-agentel-dedicated-command-prefix)
          (warashi-agentel--session-name-command options)))

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

(defun warashi-agentel--start (agent model effort &rest options)
  "AGENT の session を MODEL と EFFORT を指定して起動する。表示はしない。
AGENT は `agentel-agents' の名前。OPTIONS は `agentel-start' に足す option。"
  ;; agentel は agent をローカルで動かし、cwd もそのまま渡すので、TRAMP 先の
  ;; path では agent が作業場所を見失う。
  (when (file-remote-p default-directory)
    (user-error "agentel cannot start an agent over TRAMP: %s"
                default-directory))
  (require 'agentel)
  ;; 専用領域の判定を起動前に済ませるのは、`agentel-command-prefix' で拒否
  ;; すると作りかけの session buffer が残るため。実体のパスを渡すのは、専用
  ;; runner が作業領域を実体のパスで mount するため。
  (apply #'agentel-start
         :cwd (warashi-agentel--dedicated-directory default-directory)
         :agent agent
         :display nil
         :model model
         :effort effort
         options))

(defun warashi-agentel--variant-forms (agent variants)
  "AGENT の VARIANTS から起動コマンドを定義する form の列を返す。
VARIANTS の各要素は (NAME MODEL EFFORT)。"
  (mapcan
   (pcase-lambda (`(,name ,model ,effort))
     (let* ((label (format "%s-%s" agent name))
            (fn (intern (format "warashi-agentel-%s" label)))
            (eshell-fn (intern (format "eshell/%s" label))))
       (list
        `(defun ,fn (&rest options)
           ,(format "%s を model %s / effort %s で起動する。
OPTIONS は `agentel-start' に足す option。" agent model effort)
           (interactive)
           (apply #'warashi-agentel--start ',agent ,model ,effort options))
        `(defun ,eshell-fn (&rest _args)
           ,(format "eshell から `%s' を起動し、起動した buffer を示す。" fn)
           ;; session をそのまま返すと、eshell が struct を丸ごと出力する。
           (format ,(format "%s: started %%s" label)
                   (buffer-name (agentel-session-buffer (,fn)))))
        `(warashi-agentel-register-variant ,label ',fn))))
   variants))

(defmacro warashi-agentel-define-claude-variants (&rest variants)
  "VARIANTS から Claude の起動コマンドを定義する。
VARIANTS の各要素は (NAME MODEL EFFORT)。NAME ごとに
`warashi-agentel-claude-NAME' と、eshell から短い名前で呼ぶための
`eshell/claude-NAME' を生成する。"
  `(progn ,@(warashi-agentel--variant-forms 'claude variants)))

(defmacro warashi-agentel-define-copilot-variants (&rest variants)
  "VARIANTS から Copilot CLI の起動コマンドを定義する。
VARIANTS の各要素は (NAME MODEL EFFORT)。NAME ごとに
`warashi-agentel-copilot-NAME' と `eshell/copilot-NAME' を生成する。"
  `(progn ,@(warashi-agentel--variant-forms 'copilot variants)))

;;;; project-switch からの起動

(defun warashi-agentel-read-variant ()
  "起動する variant のコマンドを選ばせて返す。"
  (let ((name (completing-read "Agent: "
                               (mapcar #'car warashi-agentel-variants)
                               nil t)))
    (alist-get name warashi-agentel-variants nil nil #'equal)))

(defun warashi-agentel-project-switch ()
  "variant を選んで起動し、`project-switch-project' のメニューに戻る。"
  (interactive)
  (when-let* ((command (warashi-agentel-read-variant)))
    ;; `project-switch-project' は選んだ project を override に入れるだけで、
    ;; `default-directory' は呼び出し元の buffer のまま残す。
    (let ((default-directory (or project-current-directory-override
                                 default-directory)))
      (funcall command)))
  ;; メニューを開き直すのは、`project-current-directory-override' が
  ;; ディスパッチしたコマンドの終了で消えるため。起動して戻るだけでは元の
  ;; project に居る状態になり、続けて magit を開くのに project を選び直す
  ;; ことになる。M-x から呼んだときに開かないのは、戻る先のメニューが無いため。
  (when project-current-directory-override
    (project-switch-project project-current-directory-override)))

;;;; 横断作業の起動

(defcustom warashi-agentel-handoff-directory
  (expand-file-name "github.com/Warashi/brainium/brainium/"
                    warashi-chelly-workspace-root)
  "横断作業の session を起動する brainium の clone。
計画は brainium の task で立て、そこから各 repo の clone を編集する。"
  :type 'directory
  :group 'warashi-chelly-workspace)

(defun warashi-agentel-handoff-candidates ()
  "起動時に集められる handoff 名を (NAME . 参加 repo の一覧) で返す。"
  ;; 集める clone の判定を Emacs に複製しないため、chelly が shell に返す補完を読む。
  ;; stderr には cobra の終わりの報告が出るので混ぜない。TRAMP の buffer から呼んでも
  ;; ローカルの chelly に聞くよう、cwd はローカルにあるディレクトリにする。
  (with-temp-buffer
    (let ((default-directory temporary-file-directory))
      (call-process (car warashi-agentel-dedicated-command-prefix) nil '(t nil) nil
                    "__complete" "--handoff" ""))
    ;; 候補は「名前<TAB>説明」の行で、最後に :4 のような directive の行が続く。
    (delq nil
          (mapcar (lambda (line)
                    (pcase (split-string line "\t")
                      (`(,name ,repositories) (cons name repositories))))
                  (split-string (buffer-string) "\n" t)))))

(defun warashi-agentel--read-handoff ()
  "集められる handoff 名から一つ選ばせる。候補が無ければ `user-error'。"
  (let ((candidates (or (warashi-agentel-handoff-candidates)
                        (user-error "No handoff clone to collect; create one first"))))
    (completing-read
     "Handoff: "
     (lambda (string predicate action)
       (if (eq action 'metadata)
           `(metadata (annotation-function
                       . ,(lambda (name)
                            (when-let* ((repositories (cdr (assoc name candidates))))
                              (concat "  " repositories)))))
         (complete-with-action action candidates string predicate)))
     nil t)))

(defun warashi-agentel-handoff (name command)
  "brainium の clone で起動コマンド COMMAND を、handoff NAME の clone を集めて動かす。
各 repo で同じ NAME を指定して作った clone が、本人と同じ ghq の path に
mount される。session は \"NAME (handoff)\" の名前で見分ける。"
  (interactive (list (warashi-agentel--read-handoff)
                     (warashi-agentel-read-variant)))
  (when (string-empty-p name)
    (user-error "handoff name is required"))
  (let ((default-directory (file-name-as-directory warashi-agentel-handoff-directory)))
    (funcall command :handoff name :project (format "%s (handoff)" name))))

(provide 'warashi-agentel)
;;; warashi-agentel.el ends here

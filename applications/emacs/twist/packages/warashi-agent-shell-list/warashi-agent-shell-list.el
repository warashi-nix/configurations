;;; warashi-agent-shell-list.el --- agent-shell の一覧サイドバー  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (agent-shell "0.1.0"))
;; Keywords: convenience, tools

;;; Commentary:

;; 複数の agent-shell を並行で回していると、どれが permission 待ちで止まって
;; いるかを見失う。`agent-shell-switch-buffer' は同じ情報を出せるが、呼んだ
;; 瞬間しか見えないので気づきの装置にはならない。side window に常駐させ、
;; 要操作の shell を先頭に集める。
;;
;; `warashi-agent-shell-list-toggle' でサイドバーを開閉する。各 shell から
;; 状態変化を伝えるための `warashi-agent-shell-list--subscribe' と
;; `warashi-agent-shell-list--auto-open' は `agent-shell-mode-hook' に、
;; `warashi-agent-shell-list--mark-read' は window の変化を見る hook に、
;; それぞれ利用側で登録する。

;;; Code:

;; agent-shell を実行時に require しないのは、この一覧が startup 時から
;; window hook に居座る一方、shell を 1 つも開かない日もあるため。compile
;; 時だけ読ませ、load は実際に必要になる `warashi-agent-shell-list-toggle'
;; まで遅らせる。
(eval-when-compile (require 'agent-shell))
(require 'map)
(require 'seq)
(require 'subr-x)

;; agent-shell を load 時に require しないので、参照する関数はすべて
;; declare-function で宣言しておく。viewport は agent-shell 本体からも
;; 自動では読まれない。
(declare-function agent-shell-status "agent-shell")
(declare-function agent-shell-buffers "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-shell--buffer-name-prefix "agent-shell")
(declare-function agent-shell-viewport--buffer "agent-shell-viewport")
(declare-function agent-shell-viewport--shell-buffer "agent-shell-viewport")
(defvar agent-shell-prefer-viewport-interaction)

(defconst warashi-agent-shell-list-buffer-name "*agent shells*"
  "サイドバーに表示する buffer 名。")

(defconst warashi-agent-shell-list-display-action
  '(display-buffer-in-side-window
    (side . right)
    (window-width . 40)
    ;; C-x 1 で消えると気づきの装置として当てにできないので残す。
    (window-parameters . ((no-delete-other-windows . t))))
  "サイドバーの表示先。")

(defvar-local warashi-agent-shell-list--unread nil
  "ターンが終わったあと、まだ見に行っていない shell なら non-nil。")

(defun warashi-agent-shell-list--attention (shell-buffer)
  "SHELL-BUFFER の要操作度を返す。小さいほど先に並ぶ。"
  (cond ((eq (agent-shell-status :shell-buffer shell-buffer) 'blocked) 0)
        ((buffer-local-value 'warashi-agent-shell-list--unread shell-buffer) 1)
        (t 2)))

(defun warashi-agent-shell-list--indicator (shell-buffer)
  "SHELL-BUFFER の状態を表す 1 文字を返す。"
  ;; status を単語で出さないのは、幅 40 の side window では 7 桁が shell 名と
  ;; title を削るため。要操作 (! と *) と待てばよい busy が区別できれば足りる。
  (pcase (warashi-agent-shell-list--attention shell-buffer)
    (0 (propertize "!" 'face 'agent-shell-error))
    (1 (propertize "*" 'face 'agent-shell-warning))
    (_ (if (eq (agent-shell-status :shell-buffer shell-buffer) 'busy)
           (propertize "…" 'face 'shadow)
         " "))))

(defun warashi-agent-shell-list--name (shell-buffer)
  "SHELL-BUFFER の名前から agent 名の prefix を落として返す。"
  ;; "Claude Agent @ " だけで 15 桁あり、残るのがプロジェクト名の頭数文字に
  ;; なってしまう。どの shell か見分けられるのは prefix の後ろの部分。
  (let ((name (buffer-name shell-buffer)))
    (if-let* ((agent-name (map-nested-elt
                           (buffer-local-value 'agent-shell--state shell-buffer)
                           '(:agent-config :buffer-name)))
              (prefix (agent-shell--buffer-name-prefix agent-name)))
        (string-remove-prefix prefix name)
      name)))

(defun warashi-agent-shell-list--title (shell-buffer)
  "SHELL-BUFFER の session title を 1 行で返す。"
  ;; state を内部変数から読むのは、title を取得する公開 API が無いため。
  (string-trim
   (car (split-string
         (or (map-nested-elt (buffer-local-value 'agent-shell--state shell-buffer)
                             '(:session :title))
             "")
         "\n"))))

(defun warashi-agent-shell-list--insert (shell-buffer)
  "SHELL-BUFFER の行を 2 行で挿入する。"
  ;; 1 行に詰めないのは、shell 名と title は用途が違い (どれか特定する /
  ;; 何をやらせていたか思い出す)、どちらを削っても片方の用が足りなくなるため。
  (let ((start (point)))
    (insert (warashi-agent-shell-list--indicator shell-buffer)
            " "
            (propertize (warashi-agent-shell-list--name shell-buffer)
                        'face 'agent-shell-buffer-name)
            "\n  "
            (propertize (warashi-agent-shell-list--title shell-buffer)
                        'face 'agent-shell-session-title)
            "\n")
    (put-text-property start (point) 'warashi-agent-shell-list-buffer shell-buffer)))

(defun warashi-agent-shell-list--buffer-at-point ()
  "point の行が指す shell buffer を返す。"
  (get-text-property (point) 'warashi-agent-shell-list-buffer))

(defun warashi-agent-shell-list--position (shell-buffer)
  "SHELL-BUFFER の行の先頭位置を返す。無ければ nil。"
  (save-excursion
    (goto-char (point-min))
    (catch 'found
      (while (not (eobp))
        (when (eq (warashi-agent-shell-list--buffer-at-point) shell-buffer)
          (throw 'found (point)))
        (goto-char (or (next-single-property-change
                        (point) 'warashi-agent-shell-list-buffer)
                       (point-max))))
      nil)))

(defun warashi-agent-shell-list--refresh ()
  "サイドバーが見えていれば描き直す。"
  ;; 見えていないときに走らせないのは、agent が走っている間ずっと event が飛ぶため。
  (when-let* ((buffer (get-buffer warashi-agent-shell-list-buffer-name))
              ((get-buffer-window buffer t)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (previous (warashi-agent-shell-list--buffer-at-point)))
        (erase-buffer)
        (mapc #'warashi-agent-shell-list--insert
              (seq-sort-by #'warashi-agent-shell-list--attention #'<
                           (agent-shell-buffers)))
        ;; 描き直しで point が飛ぶと、選ぼうとしていた shell を見失う。
        (let ((position (or (and previous
                                 (warashi-agent-shell-list--position previous))
                            (point-min))))
          (goto-char position)
          (dolist (window (get-buffer-window-list buffer nil t))
            (set-window-point window position)))))))

(defun warashi-agent-shell-list-refresh ()
  "サイドバーを描き直す。"
  (interactive)
  (warashi-agent-shell-list--refresh))

(defun warashi-agent-shell-list-next (&optional count)
  "COUNT 個先の shell に point を移す。"
  (interactive "p")
  (dotimes (_ (or count 1))
    (when-let* ((position (next-single-property-change
                           (point) 'warashi-agent-shell-list-buffer)))
      (goto-char position))))

(defun warashi-agent-shell-list--entry-start ()
  "point が居る shell の行の先頭位置を返す。"
  (if (or (bobp)
          (not (eq (warashi-agent-shell-list--buffer-at-point)
                   (get-text-property (1- (point))
                                      'warashi-agent-shell-list-buffer))))
      (point)
    (or (previous-single-property-change (point) 'warashi-agent-shell-list-buffer)
        (point-min))))

(defun warashi-agent-shell-list-previous (&optional count)
  "COUNT 個前の shell に point を移す。"
  (interactive "p")
  (dotimes (_ (or count 1))
    ;; 先に今いる shell の先頭へ戻すのは、2 行目に point があるときに 1 回で
    ;; 2 つ戻ってしまうため。
    (goto-char (warashi-agent-shell-list--entry-start))
    (unless (bobp)
      (goto-char (or (previous-single-property-change
                      (point) 'warashi-agent-shell-list-buffer)
                     (point-min))))))

(defun warashi-agent-shell-list-switch ()
  "point の行の agent-shell に切り替える。"
  (interactive)
  (let* ((shell-buffer (or (warashi-agent-shell-list--buffer-at-point)
                           (user-error "No shell at point")))
         (target (or (when agent-shell-prefer-viewport-interaction
                       (agent-shell-viewport--buffer :shell-buffer shell-buffer
                                                     :existing-only t))
                     shell-buffer)))
    ;; side window のまま switch-to-buffer すると幅 40 の枠に shell が入るので、
    ;; side window でない window を選び直してから切り替える。
    (when-let* ((window (seq-find (lambda (window)
                                    (not (window-parameter window 'window-side)))
                                  (window-list))))
      (select-window window))
    (switch-to-buffer target)))

(defvar-keymap warashi-agent-shell-list-mode-map
  :doc "`warashi-agent-shell-list-mode' のキーマップ。"
  "RET" #'warashi-agent-shell-list-switch
  "n" #'warashi-agent-shell-list-next
  "p" #'warashi-agent-shell-list-previous
  "g" #'warashi-agent-shell-list-refresh
  "q" #'quit-window)

(define-derived-mode warashi-agent-shell-list-mode special-mode "Agent Shells"
  "agent-shell の一覧を表示する major mode。"
  ;; 折り返さないのは、幅 40 に収まらない title が 2 行に伸びて、shell 1 つが
  ;; 何行になるか分からなくなるため。
  (setq truncate-lines t))

(defun warashi-agent-shell-list--buffer ()
  "サイドバーの buffer を返す。無ければ作る。"
  (or (get-buffer warashi-agent-shell-list-buffer-name)
      (with-current-buffer (get-buffer-create warashi-agent-shell-list-buffer-name)
        (warashi-agent-shell-list-mode)
        (current-buffer))))

(defun warashi-agent-shell-list-toggle ()
  "agent-shell の一覧サイドバーを開閉する。"
  (interactive)
  (require 'agent-shell)
  (if-let* ((window (get-buffer-window warashi-agent-shell-list-buffer-name t)))
      (delete-window window)
    (display-buffer (warashi-agent-shell-list--buffer)
                    warashi-agent-shell-list-display-action)
    (warashi-agent-shell-list--refresh)))

(defconst warashi-agent-shell-list--events
  '(init-finished prompt-ready input-submitted
    permission-request permission-response
    turn-complete session-title-changed error clean-up)
  "サイドバーを描き直す agent-shell の event。")
;; agent-message-chunk を入れないのは、1 ターンに何度も飛ぶ割に一覧の見た目が
;; 変わらないため。
;; 閉じるのを自動化しないのは、見えていた欄が勝手に消えると気づきの装置として
;; 当てにできなくなるため。

(defun warashi-agent-shell-list--on-event (_event)
  "shell の状態が変わったのでサイドバーを描き直す。"
  ;; その場で描き直さないのは、clean-up が kill-buffer の途中で飛び、
  ;; 死にかけの buffer が一覧に残るため。
  (run-at-time 0 nil #'warashi-agent-shell-list--refresh))

(defun warashi-agent-shell-list--shell-buffer (buffer)
  "BUFFER が指している shell buffer を返す。shell でなければ nil。"
  (with-current-buffer buffer
    (cond ((derived-mode-p 'agent-shell-mode)
           buffer)
          ((derived-mode-p '(agent-shell-viewport-view-mode
                             agent-shell-viewport-edit-mode))
           (agent-shell-viewport--shell-buffer buffer)))))

(defun warashi-agent-shell-list--selected-shell-buffer ()
  "いま選択している window が指す shell buffer を返す。"
  (warashi-agent-shell-list--shell-buffer (window-buffer (selected-window))))

(defun warashi-agent-shell-list--mark-unread (_event)
  "ターンが終わった shell に未読の印を付ける。"
  ;; 見ている最中の shell に印を付けないのは、その場で読んだ返事が要操作として
  ;; 一覧の先頭に居座るため。
  (unless (eq (warashi-agent-shell-list--selected-shell-buffer) (current-buffer))
    (setq warashi-agent-shell-list--unread t)))

(defun warashi-agent-shell-list--mark-read (&optional _window-or-frame)
  "切り替えた先の shell の未読を落とす。"
  (when-let* ((shell-buffer (warashi-agent-shell-list--selected-shell-buffer))
              ((buffer-local-value 'warashi-agent-shell-list--unread shell-buffer)))
    (with-current-buffer shell-buffer
      (setq warashi-agent-shell-list--unread nil))
    (warashi-agent-shell-list--refresh)))

(defun warashi-agent-shell-list--subscribe ()
  "この shell の状態変化をサイドバーに伝える。"
  (dolist (event warashi-agent-shell-list--events)
    (agent-shell-subscribe-to
     :shell-buffer (current-buffer)
     :event event
     :on-event #'warashi-agent-shell-list--on-event))
  (agent-shell-subscribe-to
   :shell-buffer (current-buffer)
   :event 'turn-complete
   :on-event #'warashi-agent-shell-list--mark-unread))

(defun warashi-agent-shell-list--auto-open ()
  "最初の shell が作られたときにサイドバーを開く。"
  ;; 2 つ目以降で開き直さないのは、手動で閉じた一覧を勝手に戻さないため。
  (unless (or (get-buffer-window warashi-agent-shell-list-buffer-name t)
              (seq-remove (lambda (buffer) (eq buffer (current-buffer)))
                          (agent-shell-buffers)))
    (warashi-agent-shell-list-toggle)))

(provide 'warashi-agent-shell-list)
;;; warashi-agent-shell-list.el ends here

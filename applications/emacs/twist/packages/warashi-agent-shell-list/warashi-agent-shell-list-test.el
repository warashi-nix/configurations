;;; warashi-agent-shell-list-test.el --- 一覧サイドバーのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-agent-shell-list-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'agent-shell)
(require 'warashi-agent-shell-list)

(defvar warashi-agent-shell-list-test--statuses nil
  "shell buffer から status への alist。")

(defun warashi-agent-shell-list-test--status (&rest args)
  "テスト用の `agent-shell-status'。ARGS から :shell-buffer を読む。"
  (alist-get (plist-get args :shell-buffer)
             warashi-agent-shell-list-test--statuses))

(defmacro warashi-agent-shell-list-test--with-shells (specs &rest body)
  "SPECS から shell buffer を作り BODY を実行する。
SPECS は (VAR NAME STATUS TITLE) のリスト。VAR に buffer が束縛される。"
  (declare (indent 1))
  `(let (,@(mapcar #'car specs)
         (warashi-agent-shell-list-test--statuses nil)
         (buffers nil))
     (unwind-protect
         (progn
           ,@(mapcar
              (lambda (spec)
                (cl-destructuring-bind (var name status title) spec
                  `(progn
                     (setq ,var (generate-new-buffer ,name))
                     (push ,var buffers)
                     (push (cons ,var ,status)
                           warashi-agent-shell-list-test--statuses)
                     (with-current-buffer ,var
                       ;; agent-shell-mode を batch で起動できないので
                       ;; derived-mode-p が通る最小限だけ立てる。
                       (setq major-mode (quote agent-shell-mode))
                       (setq-local agent-shell--state
                                   (list :session (list :title ,title)))))))
              specs)
           (cl-letf (((symbol-function 'agent-shell-status)
                      #'warashi-agent-shell-list-test--status)
                     ((symbol-function 'agent-shell-buffers)
                      (lambda () (reverse buffers))))
             ,@body))
       (mapc #'kill-buffer buffers))))

(defmacro warashi-agent-shell-list-test--with-sidebar (&rest body)
  "サイドバーの buffer を表示した状態で BODY を実行する。"
  (declare (indent 0))
  `(let ((buffer (warashi-agent-shell-list--buffer)))
     (unwind-protect
         (save-window-excursion
           (set-window-buffer (selected-window) buffer)
           (with-current-buffer buffer ,@body))
       (kill-buffer buffer))))



(defun warashi-agent-shell-list-test--listed-buffers ()
  "サイドバーに並んでいる shell buffer を上から順に返す。"
  (save-excursion
    (goto-char (point-min))
    (let (buffers)
      (while (not (eobp))
        (when-let* ((buffer (warashi-agent-shell-list--buffer-at-point)))
          (cl-pushnew buffer buffers))
        (goto-char (or (next-single-property-change
                        (point) 'warashi-agent-shell-list-buffer)
                       (point-max))))
      (reverse buffers))))

;;; 並び順

(ert-deftest warashi-agent-shell-list-test-blocked-comes-first ()
  "permission 待ちの shell が先頭に来る。"
  (warashi-agent-shell-list-test--with-shells
      ((idle "idle" 'ready "")
       (blocked "blocked" 'blocked ""))
    (should (< (warashi-agent-shell-list--attention blocked)
               (warashi-agent-shell-list--attention idle)))))

(ert-deftest warashi-agent-shell-list-test-unread-comes-before-idle ()
  "未読の shell は、何もない shell より先に来る。"
  (warashi-agent-shell-list-test--with-shells
      ((idle "idle" 'ready "")
       (unread "unread" 'ready ""))
    (with-current-buffer unread
      (setq warashi-agent-shell-list--unread t))
    (should (< (warashi-agent-shell-list--attention unread)
               (warashi-agent-shell-list--attention idle)))))

(ert-deftest warashi-agent-shell-list-test-blocked-comes-before-unread ()
  "permission 待ちは未読より優先される。"
  (warashi-agent-shell-list-test--with-shells
      ((unread "unread" 'ready "")
       (blocked "blocked" 'blocked ""))
    (with-current-buffer unread
      (setq warashi-agent-shell-list--unread t))
    (should (< (warashi-agent-shell-list--attention blocked)
               (warashi-agent-shell-list--attention unread)))))

(ert-deftest warashi-agent-shell-list-test-refresh-orders-by-attention ()
  "描き直すと要操作の shell が上から順に並ぶ。"
  (warashi-agent-shell-list-test--with-shells
      ((idle "idle" 'ready "")
       (blocked "blocked" 'blocked "")
       (unread "unread" 'ready ""))
    (with-current-buffer unread
      (setq warashi-agent-shell-list--unread t))
    (warashi-agent-shell-list-test--with-sidebar
      (warashi-agent-shell-list--refresh)
      (should (equal (list blocked unread idle)
                     (warashi-agent-shell-list-test--listed-buffers))))))


;;; 表示

(ert-deftest warashi-agent-shell-list-test-indicator-distinguishes-states ()
  "要操作の 2 種と busy と待機が別の文字になる。"
  (warashi-agent-shell-list-test--with-shells
      ((blocked "blocked" 'blocked "")
       (unread "unread" 'ready "")
       (busy "busy" 'busy "")
       (idle "idle" 'ready ""))
    (with-current-buffer unread
      (setq warashi-agent-shell-list--unread t))
    (should (equal "!" (substring-no-properties
                        (warashi-agent-shell-list--indicator blocked))))
    (should (equal "*" (substring-no-properties
                        (warashi-agent-shell-list--indicator unread))))
    (should (equal "…" (substring-no-properties
                        (warashi-agent-shell-list--indicator busy))))
    (should (equal " " (substring-no-properties
                        (warashi-agent-shell-list--indicator idle))))))

(ert-deftest warashi-agent-shell-list-test-name-drops-agent-prefix ()
  "agent 名の prefix を落とした残りが名前になる。"
  (let* ((prefix (agent-shell--buffer-name-prefix "Claude Agent"))
         (buffer (generate-new-buffer (concat prefix "myproject"))))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq-local agent-shell--state
                        (list :agent-config (list :buffer-name "Claude Agent"))))
          (should (equal "myproject"
                         (warashi-agent-shell-list--name buffer))))
      (kill-buffer buffer))))

(ert-deftest warashi-agent-shell-list-test-name-falls-back-to-buffer-name ()
  "agent 名が取れなければ buffer 名をそのまま返す。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "plain" 'ready ""))
    (should (equal (buffer-name shell)
                   (warashi-agent-shell-list--name shell)))))

(ert-deftest warashi-agent-shell-list-test-title-keeps-first-line-only ()
  "title は 1 行目だけを空白を落として返す。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready "  最初の行  \n2 行目"))
    (should (equal "最初の行" (warashi-agent-shell-list--title shell)))))

(ert-deftest warashi-agent-shell-list-test-title-is-empty-without-session ()
  "session が無い shell の title は空文字。"
  (let ((buffer (generate-new-buffer "no-session")))
    (unwind-protect
        (should (equal "" (warashi-agent-shell-list--title buffer)))
      (kill-buffer buffer))))

(ert-deftest warashi-agent-shell-list-test-entry-spans-two-lines ()
  "1 つの shell は 2 行を占め、どちらの行も同じ shell を指す。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready "やっていること"))
    (warashi-agent-shell-list-test--with-sidebar
      (warashi-agent-shell-list--refresh)
      (goto-char (point-min))
      (should (eq shell (warashi-agent-shell-list--buffer-at-point)))
      (forward-line 1)
      (should (eq shell (warashi-agent-shell-list--buffer-at-point)))
      (should (string-match-p "やっていること"
                              (buffer-substring-no-properties
                               (point-min) (point-max)))))))


;;; 移動

(ert-deftest warashi-agent-shell-list-test-next-moves-one-shell ()
  "n は 2 行目を飛ばして次の shell へ移る。"
  (warashi-agent-shell-list-test--with-shells
      ((first "first" 'ready "")
       (second "second" 'ready ""))
    (warashi-agent-shell-list-test--with-sidebar
      (warashi-agent-shell-list--refresh)
      (goto-char (point-min))
      (warashi-agent-shell-list-next)
      (should (eq second (warashi-agent-shell-list--buffer-at-point))))))

(ert-deftest warashi-agent-shell-list-test-previous-moves-one-shell ()
  "p は shell の 2 行目に居ても 1 つだけ戻る。"
  (warashi-agent-shell-list-test--with-shells
      ((first "first" 'ready "")
       (second "second" 'ready ""))
    (warashi-agent-shell-list-test--with-sidebar
      (warashi-agent-shell-list--refresh)
      (goto-char (point-min))
      (warashi-agent-shell-list-next)
      (forward-line 1)
      (warashi-agent-shell-list-previous)
      (should (eq first (warashi-agent-shell-list--buffer-at-point))))))

(ert-deftest warashi-agent-shell-list-test-refresh-keeps-point-on-same-shell ()
  "描き直しても選んでいた shell の上に point が残る。"
  (warashi-agent-shell-list-test--with-shells
      ((idle "idle" 'ready "")
       (other "other" 'ready ""))
    (warashi-agent-shell-list-test--with-sidebar
      (warashi-agent-shell-list--refresh)
      (goto-char (point-min))
      (warashi-agent-shell-list-next)
      (let ((selected (warashi-agent-shell-list--buffer-at-point)))
        ;; 先頭の shell が blocked になって並び順が変わっても見失わない。
        (setf (alist-get idle warashi-agent-shell-list-test--statuses) 'blocked)
        (warashi-agent-shell-list--refresh)
        (should (eq selected (warashi-agent-shell-list--buffer-at-point)))))))


;;; 未読

(ert-deftest warashi-agent-shell-list-test-turn-complete-marks-unread ()
  "見ていない shell のターンが終わると未読になる。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready ""))
    (with-current-buffer shell
      (warashi-agent-shell-list--mark-unread nil)
      (should warashi-agent-shell-list--unread))))

(ert-deftest warashi-agent-shell-list-test-visiting-shell-is-not-marked-unread ()
  "見ている最中の shell はターンが終わっても未読にならない。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready ""))
    (with-current-buffer shell
      (save-window-excursion
        (set-window-buffer (selected-window) shell)
        (warashi-agent-shell-list--mark-unread nil))
      (should-not warashi-agent-shell-list--unread))))

(ert-deftest warashi-agent-shell-list-test-visiting-shell-clears-unread ()
  "未読の shell に切り替えると印が落ちる。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready ""))
    (with-current-buffer shell
      (setq warashi-agent-shell-list--unread t)
      (save-window-excursion
        (set-window-buffer (selected-window) shell)
        (warashi-agent-shell-list--mark-read))
      (should-not warashi-agent-shell-list--unread))))

(ert-deftest warashi-agent-shell-list-test-non-shell-buffer-clears-nothing ()
  "shell でない buffer に居るときは未読を落とさない。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready ""))
    (with-current-buffer shell
      (setq warashi-agent-shell-list--unread t))
    (with-temp-buffer
      (warashi-agent-shell-list--mark-read))
    (should (buffer-local-value 'warashi-agent-shell-list--unread shell))))


;;; サイドバーの開閉

(ert-deftest warashi-agent-shell-list-test-toggle-opens-and-closes ()
  "開いたサイドバーは、もう一度呼ぶと閉じる。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready ""))
    (unwind-protect
        (save-window-excursion
          (warashi-agent-shell-list-toggle)
          (should (get-buffer-window warashi-agent-shell-list-buffer-name t))
          (warashi-agent-shell-list-toggle)
          (should-not (get-buffer-window warashi-agent-shell-list-buffer-name t)))
      (when-let* ((buffer (get-buffer warashi-agent-shell-list-buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest warashi-agent-shell-list-test-toggle-skips-other-window ()
  "開いたサイドバーは `other-window' の巡回に入らない。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready ""))
    (unwind-protect
        (save-window-excursion
          (warashi-agent-shell-list-toggle)
          (should (window-parameter
                   (get-buffer-window warashi-agent-shell-list-buffer-name t)
                   'no-other-window)))
      (when-let* ((buffer (get-buffer warashi-agent-shell-list-buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest warashi-agent-shell-list-test-toggle-selects-sidebar ()
  "見えているサイドバーが選ばれていなければ、閉じずにそこへ移る。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready ""))
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) shell)
          (let ((origin (selected-window)))
            (warashi-agent-shell-list-toggle)
            (select-window origin)
            (warashi-agent-shell-list-toggle)
            (should (eq (selected-window)
                        (get-buffer-window
                         warashi-agent-shell-list-buffer-name t)))))
      (when-let* ((buffer (get-buffer warashi-agent-shell-list-buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest warashi-agent-shell-list-test-auto-open-keeps-focus ()
  "自動で開いたサイドバーには移らない。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready ""))
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) shell)
          (let ((origin (selected-window)))
            (with-current-buffer shell
              (warashi-agent-shell-list--auto-open))
            (should (get-buffer-window warashi-agent-shell-list-buffer-name t))
            (should (eq (selected-window) origin))))
      (when-let* ((buffer (get-buffer warashi-agent-shell-list-buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest warashi-agent-shell-list-test-refresh-skips-hidden-sidebar ()
  "見えていないサイドバーは描き直さない。"
  (warashi-agent-shell-list-test--with-shells
      ((shell "shell" 'ready ""))
    (let ((buffer (warashi-agent-shell-list--buffer)))
      (unwind-protect
          (progn
            (warashi-agent-shell-list--refresh)
            (should (equal "" (with-current-buffer buffer
                                (buffer-string)))))
        (kill-buffer buffer)))))

;;; warashi-agent-shell-list-test.el ends here

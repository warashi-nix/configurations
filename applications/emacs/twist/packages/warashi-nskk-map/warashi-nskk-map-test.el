;;; warashi-nskk-map-test.el --- キーマップ包み直しのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-nskk-map-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nskk)
(require 'warashi-nskk-map)

;; 学習データを ~/.emacs.d に書き出させない。保存は kill-emacs-hook でも走るので
;; let 束縛では間に合わない。
(setq nskk-search-learning-file
      (expand-file-name "warashi-nskk-map-test-learning.dat" temporary-file-directory))
(setq nskk-study-file
      (expand-file-name "warashi-nskk-map-test-study.dat" temporary-file-directory))

(defmacro warashi-nskk-map-test--with-mode (mode &rest body)
  "nskk-mode を MODE で有効にしたバッファで BODY を実行する。"
  (declare (indent 1))
  `(with-temp-buffer
     (electric-indent-local-mode -1)
     (nskk-mode 1)
     (nskk--set-mode ,mode)
     (unwind-protect (progn ,@body)
       (ignore-errors (nskk-mode -1)))))

(defun warashi-nskk-map-test--command (name)
  "テスト用のコマンド NAME を作って返す。"
  (defalias name (lambda () (interactive) name))
(defun warashi-nskk-map-test--lookup (key)
  "包み直した後の KEY の解決結果を返す。
`keymap-lookup' は menu-item の `:filter' を適用するので、いま打鍵したのが
KEY だという状況を作ってから引く。"
  (let ((last-input-event (aref (key-parse key) 0)))
    (keymap-lookup nskk-mode-map key)))

  name)

;;;; 有効条件

(ert-deftest warashi-nskk-map-test-filter-follows-mode ()
  "かなモードでだけ nskk のバインドを生かす。"
  (warashi-nskk-map-test--with-mode 'hiragana
    (let ((last-input-event ?q))
      (should (eq 'cmd (warashi-nskk-map--filter 'cmd)))))
  (warashi-nskk-map-test--with-mode 'ascii
    (let ((last-input-event ?q))
      (should-not (warashi-nskk-map--filter 'cmd)))))

(ert-deftest warashi-nskk-map-test-filter-defers-in-read-only ()
  "read-only バッファでは major mode の単キーコマンドに譲る。"
  (warashi-nskk-map-test--with-mode 'hiragana
    (setq buffer-read-only t)
    (let ((last-input-event ?q))
      (should-not (warashi-nskk-map--filter 'cmd)))))

(ert-deftest warashi-nskk-map-test-filter-matches-translate ()
  "キーマップ側の判定が `warashi-nskk-im-translate' とずれない。
両者がずれると、同じバッファで a は major mode に降りるのに q だけ nskk に
吸われる、という不整合になる。"
  (dolist (mode '(hiragana katakana ascii))
    (warashi-nskk-map-test--with-mode mode
      (dolist (read-only '(nil t))
        (setq buffer-read-only read-only)
        (dolist (key '(?a ?q ?\s ?~))
          (let ((last-input-event key))
            (should (eq (and (warashi-nskk-map--filter 'cmd) t)
                        (symbolp (car (warashi-nskk-im-translate key)))))))))))

(ert-deftest warashi-nskk-map-test-mode-switch-filter-ignores-mode ()
  "C-j はモードに依らず生かす。ascii から かなへ戻る唯一の打鍵なので。"
  (warashi-nskk-map-test--with-mode 'ascii
    (let ((last-input-event ?\C-j))
      (should (eq 'cmd (warashi-nskk-map--mode-switch-filter 'cmd))))
    (setq buffer-read-only t)
    (let ((last-input-event ?\C-j))
      (should-not (warashi-nskk-map--mode-switch-filter 'cmd)))))
(ert-deftest warashi-nskk-map-test-wrap-binding-keeps-original ()
  "包んだキーは元のコマンドに解決し、控えにも残る。"
  (let ((nskk-mode-map (make-sparse-keymap))
        (warashi-nskk-map--originals nil)
        (cmd (warashi-nskk-map-test--command 'warashi-nskk-map-test--cmd)))
    (define-key nskk-mode-map (kbd "q") cmd)
    (warashi-nskk-map--wrap-binding (kbd "q") cmd #'warashi-nskk-map--filter)
    (should (equal (list (cons (kbd "q") cmd)) warashi-nskk-map--originals))
    (warashi-nskk-map-test--with-mode 'hiragana
      (should (eq cmd (warashi-nskk-map-test--lookup "q"))))))

(ert-deftest warashi-nskk-map-test-wrap-resolves-to-original-when-active ()
  "包んでも、nskk が取るべき打鍵では元のコマンドに解決する。"
  (let ((nskk-mode-map (make-sparse-keymap))
        (warashi-nskk-map--originals nil)
        (cmd (warashi-nskk-map-test--command 'warashi-nskk-map-test--q)))
    (define-key nskk-mode-map (kbd "q") cmd)
    (warashi-nskk-map-wrap)
    (warashi-nskk-map-test--with-mode 'hiragana
      (should (eq cmd (warashi-nskk-map-test--lookup "q")))
      ;; read-only バッファでは major mode の単キーコマンドに譲る。
      (setq buffer-read-only t)
      (should-not (warashi-nskk-map-test--lookup "q")))
    (warashi-nskk-map-test--with-mode 'ascii
      (should-not (warashi-nskk-map-test--lookup "q")))))

(ert-deftest warashi-nskk-map-test-wrap-leaves-c-x-alone ()
  "C-x は包まない。C-x C-j をモードに依らず切替の入口として残すため。"
  (let* ((nskk-mode-map (make-sparse-keymap))
         (warashi-nskk-map--originals nil)
         (sub (make-sparse-keymap)))
    (define-key sub (kbd "C-j") (warashi-nskk-map-test--command
                                 'warashi-nskk-map-test--toggle))
    (define-key nskk-mode-map (kbd "C-x") sub)
    (warashi-nskk-map-wrap)
    (should (eq sub (keymap-lookup nskk-mode-map "C-x")))
    (should-not warashi-nskk-map--originals)))

(ert-deftest warashi-nskk-map-test-wrap-keeps-c-j-across-modes ()
  "C-j はモードに依らず解決する。ascii から かなへ戻る唯一の打鍵なので。"
  (let ((nskk-mode-map (make-sparse-keymap))
        (warashi-nskk-map--originals nil)
        (cmd (warashi-nskk-map-test--command 'warashi-nskk-map-test--kana)))
    (define-key nskk-mode-map (kbd "C-j") cmd)
    (warashi-nskk-map-wrap)
    (warashi-nskk-map-test--with-mode 'ascii
      (should (eq cmd (warashi-nskk-map-test--lookup "C-j")))
      (setq buffer-read-only t)
      (should-not (warashi-nskk-map-test--lookup "C-j")))))

(ert-deftest warashi-nskk-map-test-wrap-covers-remaps ()
  "remap 配下も包む。打鍵の取り込みは remap 一本に載っているため。"
  (let ((nskk-mode-map (make-sparse-keymap))
        (warashi-nskk-map--originals nil)
        (cmd (warashi-nskk-map-test--command 'warashi-nskk-map-test--insert)))
    (define-key nskk-mode-map [remap self-insert-command] cmd)
    (warashi-nskk-map-wrap)
    (warashi-nskk-map-test--with-mode 'hiragana
      (let ((last-input-event ?a))
        (should (eq cmd (keymap-lookup nskk-mode-map
                                       "<remap> <self-insert-command>")))))
    (warashi-nskk-map-test--with-mode 'ascii
      (let ((last-input-event ?a))
        (should-not (keymap-lookup nskk-mode-map
                                   "<remap> <self-insert-command>"))))))

(ert-deftest warashi-nskk-map-test-wrap-skips-non-commands ()
  "コマンドでないバインドは触らない。"
  (let ((nskk-mode-map (make-sparse-keymap))
        (warashi-nskk-map--originals nil))
    (define-key nskk-mode-map (kbd "z") 'warashi-nskk-map-test--undefined)
    (warashi-nskk-map-wrap)
    (should (eq 'warashi-nskk-map-test--undefined (keymap-lookup nskk-mode-map "z")))
    (should-not warashi-nskk-map--originals)))

;;;; nskk 側への辻褄合わせ

(ert-deftest warashi-nskk-map-test-restore-bound-commands ()
  "包んで漏れたコマンドを nskk--bound-commands に足し戻す。
menu-item は `commandp' が nil を返すので、放っておくと nskk 自身のハンドラが
「知らないコマンド」扱いになって ▽ 中に確定が走る。"
  (let* ((cmd (warashi-nskk-map-test--command 'warashi-nskk-map-test--bound))
         (warashi-nskk-map--originals (list (cons (kbd "q") cmd)))
         (nskk--bound-commands '(nskk-self-insert)))
    (warashi-nskk-map-restore-bound-commands)
    (should (memq cmd nskk--bound-commands))
    (should (memq 'nskk-self-insert nskk--bound-commands))))

(provide 'warashi-nskk-map-test)
;;; warashi-nskk-map-test.el ends here

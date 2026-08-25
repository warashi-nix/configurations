;;; warashi-nskk-im-test.el --- 合成イベント経路のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-nskk-im-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nskk)
(require 'warashi-nskk-im)

;; 学習データを ~/.emacs.d に書き出させない。保存は kill-emacs-hook でも走るので
;; let 束縛では間に合わない。
(setq nskk-search-learning-file
      (expand-file-name "warashi-nskk-im-test-learning.dat" temporary-file-directory))
(setq nskk-study-file
      (expand-file-name "warashi-nskk-im-test-study.dat" temporary-file-directory))

(defmacro warashi-nskk-im-test--with-mode (mode &rest body)
  "nskk-mode を MODE で有効にしたバッファで BODY を実行する。"
  (declare (indent 1))
  `(with-temp-buffer
     (electric-indent-local-mode -1)
     (nskk-mode 1)
     (nskk--set-mode ,mode)
     (unwind-protect (progn ,@body)
       (ignore-errors (nskk-mode -1)))))

;;;; 合成イベントの往復

(ert-deftest warashi-nskk-im-test-event-roundtrip ()
  "合成イベントは元の文字へ戻せる。"
  (cl-loop for char from 32 to 126
           do (should (equal char
                             (warashi-nskk-im--event-char
                              (warashi-nskk-im--event char))))))

(ert-deftest warashi-nskk-im-test-event-char-rejects-others ()
  "合成イベントでないものからは文字を取り出さない。"
  (should-not (warashi-nskk-im--event-char ?a))
  (should-not (warashi-nskk-im--event-char 'return))
  (should-not (warashi-nskk-im--event-char [?a]))
  (should-not (warashi-nskk-im--event-char nil))
  ;; 接頭辞だけ合っていても、数字でなければ文字は取り出せない。
  (should-not (warashi-nskk-im--event-char 'warashi-nskk-key-foo)))

;;;; 差し替えを見送る条件

(ert-deftest warashi-nskk-im-test-defer-p-plain-buffer ()
  "素の書き込み可能なバッファでは見送らない。"
  (with-temp-buffer
    (should-not (warashi-nskk-im--defer-p ?a))))

(ert-deftest warashi-nskk-im-test-defer-p-read-only-buffer ()
  "read-only バッファでは major mode の単キーコマンドを残す。"
  (with-temp-buffer
    (setq buffer-read-only t)
    (should (warashi-nskk-im--defer-p ?a))
    (let ((inhibit-read-only t))
      (should-not (warashi-nskk-im--defer-p ?a)))))

(ert-deftest warashi-nskk-im-test-defer-p-read-only-text ()
  "read-only かつ front-sticky なテキスト上でも見送る。"
  (with-temp-buffer
    (insert (propertize "x" 'read-only t 'front-sticky t))
    (goto-char (point-min))
    (should (warashi-nskk-im--defer-p ?a)))
  ;; front-sticky が無ければ挿入は前の文字の属性に従うので、打鍵は通す。
  (with-temp-buffer
    (insert (propertize "x" 'read-only t))
    (goto-char (point-min))
    (should-not (warashi-nskk-im--defer-p ?a))))

(ert-deftest warashi-nskk-im-test-defer-p-transient-map ()
  "transient map が握るキーは前置引数のために譲る。"
  (with-temp-buffer
    (let ((overriding-terminal-local-map universal-argument-map))
      (should (warashi-nskk-im--defer-p ?5))
      (should-not (warashi-nskk-im--defer-p ?a)))
    (let ((overriding-local-map (make-sparse-keymap)))
      (should (warashi-nskk-im--defer-p ?a)))))

;;;; 打鍵の差し替え

(ert-deftest warashi-nskk-im-test-translate-in-kana ()
  "かなモードでは印字可能キーを合成イベントに差し替える。"
  (warashi-nskk-im-test--with-mode 'hiragana
    (should (equal (list (warashi-nskk-im--event ?a))
                   (warashi-nskk-im-translate ?a)))
    (should (equal (list (warashi-nskk-im--event ?\s))
                   (warashi-nskk-im-translate ?\s)))))

(ert-deftest warashi-nskk-im-test-translate-in-ascii ()
  "ascii モードでは差し替えず、major mode の単キーコマンドを潰さない。"
  (warashi-nskk-im-test--with-mode 'ascii
    (should (equal (list ?a) (warashi-nskk-im-translate ?a)))))

(ert-deftest warashi-nskk-im-test-translate-without-nskk ()
  "nskk-mode が無効なバッファでは何も差し替えない。"
  (with-temp-buffer
    (should (equal (list ?a) (warashi-nskk-im-translate ?a)))))

(ert-deftest warashi-nskk-im-test-translate-passes-non-printing ()
  "印字可能 ASCII の外は素通しする。prefix key や制御キーを壊さないため。"
  (warashi-nskk-im-test--with-mode 'hiragana
    (dolist (key (list ?\C-x ?\C-j ?\t ?\r ?\e 127 ?あ))
      (should (equal (list key) (warashi-nskk-im-translate key))))
    ;; マウスイベントのような非整数キーもそのまま返す。
    (should (equal (list 'mouse-1) (warashi-nskk-im-translate 'mouse-1)))))

(ert-deftest warashi-nskk-im-test-translate-defers ()
  "見送る条件では、かなモードでも素通しする。"
  (warashi-nskk-im-test--with-mode 'hiragana
    (setq buffer-read-only t)
    (should (equal (list ?a) (warashi-nskk-im-translate ?a)))))

;;;; 橋渡し

(ert-deftest warashi-nskk-im-test-dispatch-uses-nskk-binding ()
  "合成イベントは nskk-mode-map 本来のハンドラへ渡る。"
  (warashi-nskk-im-test--with-mode 'hiragana
    (let ((called nil)
          (nskk-mode-map (copy-keymap nskk-mode-map)))
      (keymap-set nskk-mode-map "a"
                  (lambda () (interactive) (setq called last-command-event)))
      (let ((last-command-event (warashi-nskk-im--event ?a))
            (this-command nil))
        (warashi-nskk-im--dispatch)
        ;; ハンドラからは元の文字として見える。
        (should (equal ?a called))
        ;; corfu-auto は corfu-auto-commands を this-command で照合するので、
        ;; 橋渡し役ではなく実際に走るコマンドが残っている必要がある。
        (should (equal (keymap-lookup nskk-mode-map "a") this-command))))))

(ert-deftest warashi-nskk-im-test-dispatch-falls-back-to-self-insert ()
  "nskk-mode-map に無いキーは nskk-self-insert へ落とす。"
  (warashi-nskk-im-test--with-mode 'hiragana
    (let ((nskk-mode-map (make-sparse-keymap))
          (ran nil))
      (cl-letf (((symbol-function 'call-interactively)
                 (lambda (cmd &rest _) (setq ran cmd))))
        (let ((last-command-event (warashi-nskk-im--event ?a))
              (this-command nil))
          (warashi-nskk-im--dispatch)
          (should (eq #'nskk-self-insert ran))
          (should (eq #'nskk-self-insert this-command)))))))

(ert-deftest warashi-nskk-im-test-dispatch-ignores-other-events ()
  "合成イベント以外では何もしない。"
  (let ((ran nil))
    (cl-letf (((symbol-function 'call-interactively)
               (lambda (cmd &rest _) (setq ran cmd))))
      (let ((last-command-event ?a))
        (warashi-nskk-im--dispatch)
        (should-not ran)))))

;;;; 配線

(ert-deftest warashi-nskk-im-test-dispatch-bindings-cover-translate-range ()
  "translate が作りうる合成イベントは全て橋渡しにバインドされている。"
  (let ((nskk-mode-map (make-sparse-keymap)))
    (warashi-nskk-im-install-dispatch-bindings)
    (warashi-nskk-im-test--with-mode 'hiragana
      (cl-loop for char from 0 to 255
               for translated = (car (warashi-nskk-im-translate char))
               when (symbolp translated)
               do (should (eq #'warashi-nskk-im--dispatch
                              (keymap-lookup nskk-mode-map
                                             (key-description (vector translated)))))))))

(ert-deftest warashi-nskk-im-test-setup-is-buffer-local ()
  "input-method-function の差し替えは他のバッファに漏れない。"
  (with-temp-buffer
    (warashi-nskk-im-setup)
    (should (eq #'warashi-nskk-im-translate input-method-function))
    (should (local-variable-p 'input-method-function)))
  (with-temp-buffer
    (should-not (eq #'warashi-nskk-im-translate input-method-function))))

(ert-deftest warashi-nskk-im-test-activate-toggles-global-mode ()
  "入力メソッドの有効・無効が nskk-global-mode に対応する。"
  (let ((deactivate-current-input-method-function nil))
    (unwind-protect
        (progn
          (warashi-nskk-im-activate)
          (should (bound-and-true-p nskk-global-mode))
          (should (eq #'warashi-nskk-im-deactivate
                      deactivate-current-input-method-function))
          (warashi-nskk-im-deactivate)
          (should-not (bound-and-true-p nskk-global-mode)))
      (nskk-global-mode -1))))

(provide 'warashi-nskk-im-test)
;;; warashi-nskk-im-test.el ends here

;;; warashi-nskk-im-contract-test.el --- 上流 nskk との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-nskk-im が nskk に対して前提にしている呼び出し形を、実物へ突き
;; 当てて検証する。単体テストは nskk を require するが打鍵の経路は自前で
;; 組み立てるため、nskk 側のシンボルが改名・削除されても緑のまま通る。
;;
;; twist の env でのみ成立する。just test-emacs の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'nskk)
(require 'nskk-prolog)
(require 'warashi-nskk-im)

(defmacro warashi-nskk-im-contract-test--with-mode (mode &rest body)
  "nskk-mode を MODE で有効にしたバッファで BODY を実行する。"
  (declare (indent 1))
  `(with-temp-buffer
     (nskk-mode 1)
     (nskk-set-mode ,mode)
     (unwind-protect (progn ,@body)
       (ignore-errors (nskk-mode -1)))))

(ert-deftest warashi-nskk-im-contract-test-mode ()
  "nskk-mode の有効化と hook の口が変わっていない。"
  (should (equal '(0 . 1) (func-arity 'nskk-mode)))
  (should (boundp 'nskk-mode-hook))
  (should (boundp 'nskk-mode-map)))

(ert-deftest warashi-nskk-im-contract-test-state ()
  "かな/英数の判定に使う状態の口が変わっていない。"
  (should (boundp 'nskk-current-state))
  (should (equal '(0 . 0) (func-arity 'nskk-state-get-mode)))
  (should (equal '(2 . 2) (func-arity 'nskk-prolog-query-value))))

(ert-deftest warashi-nskk-im-contract-test-self-insert ()
  "打鍵を nskk に渡す口が変わっていない。"
  (should (equal '(1 . 1) (func-arity 'nskk-self-insert))))

(ert-deftest warashi-nskk-im-contract-test-hiragana-entry ()
  "有効化した直後にかなへ進める口が変わっていない。"
  (should (fboundp 'nskk-set-mode-hiragana))
  (warashi-nskk-im-contract-test--with-mode 'ascii
    (nskk-set-mode-hiragana)
    (should (eq 'hiragana (nskk-state-get-mode)))))

(ert-deftest warashi-nskk-im-contract-test-modeline-indicator ()
  "状態表示は状態ごとに違う文字列を返す。"
  (let ((hiragana (warashi-nskk-im-contract-test--with-mode 'hiragana
                    (nskk-modeline-indicator)))
        (katakana (warashi-nskk-im-contract-test--with-mode 'katakana
                    (nskk-modeline-indicator))))
    (should (stringp hiragana))
    (should-not (equal hiragana katakana))))

(ert-deftest warashi-nskk-im-contract-test-modeline-update-hook-point ()
  "状態が変わると nskk は nskk-modeline-update を通る。"
  ;; 表示の更新はここに付けた advice だけが担う。呼ばれなくなると表示は
  ;; 有効化した時点の状態で固まる。
  (let* ((called nil)
         (probe (lambda (&rest _) (setq called t))))
    (advice-add 'nskk-modeline-update :after probe)
    (unwind-protect
        (warashi-nskk-im-contract-test--with-mode 'ascii
          (setq called nil)
          (nskk-set-mode-hiragana)
          (should called))
      (advice-remove 'nskk-modeline-update probe))))

(ert-deftest warashi-nskk-im-contract-test-input-method-title ()
  "Emacs は入力メソッドの title を mode-line 左端に描き、文字列なら残す。"
  ;; `activate-input-method' が title を登録時の TITLE で上書きする形に戻ると、
  ;; 左端の表示は空になる。
  (should (local-variable-if-set-p 'current-input-method-title))
  (should (memq 'current-input-method-title
                (flatten-tree (default-value 'mode-line-mule-info))))
  (let ((input-method-alist nil)
        (current-input-method nil))
    (register-input-method
     "warashi-nskk-contract-test" "Japanese"
     (lambda (&optional _name) (setq current-input-method-title "写した"))
     "登録時の TITLE" "contract test")
    (with-temp-buffer
      (activate-input-method "warashi-nskk-contract-test")
      (should (equal "写した" current-input-method-title)))))

(provide 'warashi-nskk-im-contract-test)
;;; warashi-nskk-im-contract-test.el ends here

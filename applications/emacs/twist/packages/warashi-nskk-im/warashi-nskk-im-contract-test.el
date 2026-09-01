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

(ert-deftest warashi-nskk-im-contract-test-mode ()
  "nskk-mode の有効化と hook の口が変わっていない。"
  (should (equal '(0 . 1) (func-arity 'nskk-mode)))
  (should (equal '(0 . 1) (func-arity 'nskk-global-mode)))
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

(provide 'warashi-nskk-im-contract-test)
;;; warashi-nskk-im-contract-test.el ends here

;;; warashi-nskk-sticky-contract-test.el --- 上流 nskk との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-nskk-sticky が nskk に対して前提にしている呼び出し形を、実物へ
;; 突き当てて検証する。単体テストは nskk--implicit-kakutei-needed-p や
;; nskk--setup-henkan-start-marker を cl-letf で差し替えるので、上流がそれ
;; らを改名・削除しても緑のまま通る。
;;
;; twist の env でのみ成立する。just test-emacs の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'nskk)
(require 'warashi-nskk-sticky)

(ert-deftest warashi-nskk-sticky-contract-test-sticky-shift ()
  "sticky shift の受け口と保留状態が変わっていない。"
  (should (equal '(0 . 0) (func-arity 'nskk--sticky-shift-dispatch)))
  (should (boundp 'nskk--sticky-shift-pending)))

(ert-deftest warashi-nskk-sticky-contract-test-restart-henkan ()
  "▽ を張り直すのに使う口が変わっていない。"
  (should (equal '(0 . 0) (func-arity 'nskk--implicit-kakutei-needed-p)))
  (should (equal '(1 . 1) (func-arity 'nskk--setup-henkan-start-marker)))
  (should (equal '(0 . 0) (func-arity 'nskk-commit-current)))
  (should (equal '(1 . 1) (func-arity 'nskk-self-insert))))

(provide 'warashi-nskk-sticky-contract-test)
;;; warashi-nskk-sticky-contract-test.el ends here

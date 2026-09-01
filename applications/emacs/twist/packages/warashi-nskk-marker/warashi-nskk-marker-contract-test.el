;;; warashi-nskk-marker-contract-test.el --- 上流 nskk との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-nskk-marker が nskk に対して前提にしている呼び出し形を、実物へ
;; 突き当てて検証する。単体テストは advice-add を cl-letf で差し替えるので、
;; advice を張る先が実在するかを見ていない。
;;
;; twist の env でのみ成立する。just test-emacs の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'nskk)
(require 'nskk-henkan)
(require 'warashi-nskk-marker)

(ert-deftest warashi-nskk-marker-contract-test-advice-targets ()
  "▽▼ の出し入れに advice を張る先が実在する。"
  (should (equal '(1 . 1) (func-arity 'nskk-insert-marker)))
  (should (equal '(2 . 2) (func-arity 'nskk--delete-marker-at)))
  (should (equal '(3 . 3) (func-arity 'nskk--replace-marker-at))))

(provide 'warashi-nskk-marker-contract-test)
;;; warashi-nskk-marker-contract-test.el ends here

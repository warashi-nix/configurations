;;; warashi-nskk-cursor-contract-test.el --- 上流 nskk との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-nskk-cursor が nskk に対して前提にしている呼び出し形を、実物へ
;; 突き当てて検証する。単体テストは send-string-to-terminal を cl-letf で
;; 差し替えて TTY への出力だけを見るので、nskk 側の口は検証されない。
;;
;; twist の env でのみ成立する。just test-emacs の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'nskk)
(require 'warashi-nskk-cursor)

(ert-deftest warashi-nskk-cursor-contract-test-cursor ()
  "カーソル色の更新と復帰の口が変わっていない。"
  (should (equal '(0 . 0) (func-arity 'nskk-cursor-update)))
  (should (equal '(0 . 2) (func-arity 'nskk-cursor-color-restore)))
  (should (equal '(1 . 1) (func-arity 'nskk--cursor-with-color)))
  (should (equal '(0 . 1) (func-arity 'nskk--other-nskk-buffers-active-p)))
  (should (boundp 'nskk-use-color-cursor)))

(ert-deftest warashi-nskk-cursor-contract-test-state ()
  "どのモードにいるかを引く口が変わっていない。"
  (should (boundp 'nskk-current-state))
  (should (equal '(1 . 1) (func-arity 'nskk-state-mode)))
  (should (equal '(0 . 1) (func-arity 'nskk-mode))))

(provide 'warashi-nskk-cursor-contract-test)
;;; warashi-nskk-cursor-contract-test.el ends here

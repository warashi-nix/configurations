;;; warashi-nskk-map-contract-test.el --- 上流 nskk との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-nskk-map が nskk に対して前提にしている呼び出し形を、実物へ突き
;; 当てて検証する。単体テストは keymap を自前で組んで検証するため、nskk 側
;; のシンボルが改名・削除されても緑のまま通る。
;;
;; twist の env でのみ成立する。just test-emacs の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'nskk)
(require 'warashi-nskk-map)

(ert-deftest warashi-nskk-map-contract-test-bound-commands ()
  "差し替え対象を数え上げる `nskk--bound-commands' が変数として在る。
nskk が単キーに束縛したコマンドの一覧で、これを元に remap を張り直してい
る。公開されている同等の一覧が無いのでここを読んでいる。"
  (should (boundp 'nskk--bound-commands)))

(ert-deftest warashi-nskk-map-contract-test-mode ()
  "keymap と hook の口が変わっていない。"
  (should (boundp 'nskk-mode-map))
  (should (boundp 'nskk-mode-hook))
  (should (equal '(0 . 1) (func-arity 'nskk-global-mode))))

(provide 'warashi-nskk-map-contract-test)
;;; warashi-nskk-map-contract-test.el ends here

;;; nskk-corfu-henkan-contract-test.el --- 上流 nskk との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; nskk-corfu-henkan が nskk に対して前提にしている呼び出し形を、実物へ突
;; き当てて検証する。
;;
;; 単体テスト (nskk-corfu-henkan-test.el) はモック辞書を積んだうえで実物の
;; nskk を駆動するので、多くの依存はそちらでも壊れれば落ちる。ここが拾うの
;; は、単体テストが cl-letf で差し替える nskk-search-learn と、テストの経路
;; に乗らない private な補助関数群。
;;
;; twist の env でのみ成立する。素の Emacs には nskk が無いため、
;; just test-emacs の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'nskk)
(require 'nskk-henkan)
(require 'nskk-study)
(require 'nskk-annotation)
(require 'nskk-prolog)
(require 'nskk-corfu-henkan)

;;;; 見出しの切り出し

(ert-deftest nskk-corfu-henkan-contract-test-conversion-start ()
  "▽ の開始位置と marker 位置を引く口が変わっていない。"
  (should (equal '(0 . 0) (func-arity 'nskk-get-conversion-start)))
  (should (equal '(2 . 2) (func-arity 'nskk--skip-marker-pos)))
  (should (equal '(0 . 0) (func-arity 'nskk--clear-conversion-start-marker)))
  (should (boundp 'nskk-henkan-on-marker-regexp)))

(ert-deftest nskk-corfu-henkan-contract-test-state ()
  "変換状態の読み書きの口が変わっていない。"
  (should (boundp 'nskk-current-state))
  (should (equal '(2 . 2) (func-arity 'nskk-state-set-henkan-phase)))
  (should (equal '(0 . 0) (func-arity 'nskk-reset-romaji-buffer)))
  (should (fboundp 'nskk-with-current-state))
  (should (macrop 'nskk-with-current-state)))

;;;; 候補の検索

(ert-deftest nskk-corfu-henkan-contract-test-search ()
  "候補の exact 引きと前方一致引きの口が変わっていない。"
  (should (equal '(1 . 5) (func-arity 'nskk-core-search/k)))
  (should (equal '(1 . 1) (func-arity 'nskk--dcomp-search-prefix)))
  (should (equal '(2 . 2) (func-arity 'nskk--search-reading-score))))

(ert-deftest nskk-corfu-henkan-contract-test-study ()
  "学習の並べ替えと確定通知の口が変わっていない。
nskk-search-learn は単体テストが cl-letf で差し替えるので、実物の arity を
見るのはここだけ。"
  (should (equal '(2 . 3) (func-arity 'nskk-search-learn)))
  (should (equal '(2 . 2) (func-arity 'nskk-study-reorder)))
  (should (equal '(2 . 3) (func-arity 'nskk-study-after-kakutei))))

;;;; 注釈

(ert-deftest nskk-corfu-henkan-contract-test-annotation ()
  "注釈の引き当てと整形の口が変わっていない。"
  (should (equal '(2 . 2) (func-arity 'nskk-annotation-lookup)))
  (should (equal '(1 . 1) (func-arity 'nskk--annotation-format)))
  (should (boundp 'nskk-show-annotation)))

;;;; 打鍵の受け口

(ert-deftest nskk-corfu-henkan-contract-test-input ()
  "打鍵を nskk に戻す口が変わっていない。"
  (should (equal '(1 . 1) (func-arity 'nskk-self-insert)))
  (should (equal '(0 . 0) (func-arity 'nskk-handle-backspace)))
  (should (equal '(0 . 0) (func-arity 'nskk-completion-at-point)))
  (should (equal '(2 . 2) (func-arity 'nskk-prolog-query-value))))

(provide 'nskk-corfu-henkan-contract-test)
;;; nskk-corfu-henkan-contract-test.el ends here

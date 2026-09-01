;;; warashi-pkm-capture-contract-test.el --- 上流依存との契約テスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; warashi-pkm-capture が Emacs 同梱のライブラリに対して前提にしている呼び
;; 出し形を、実物へ突き当てて検証する。上流は Emacs 本体なので改名の頻度は
;; 低いが、壊れ方は他と同じで、単体テストが差し替えている限り気付けない。
;;
;; twist の env でのみ成立する。just test-emacs の対象からは自然に外れる。

;;; Code:

(require 'ert)
(require 'org-id)
(require 'iso8601)
(require 'url-http)
(require 'warashi-pkm-capture)

(ert-deftest warashi-pkm-capture-contract-test-capture-format ()
  "capture の PROPERTIES に載せる ID と日時の口が変わっていない。
`:CAPTURED:' は org-capture テンプレートが生成する書式と揃える必要があり、
`org-time-stamp-format' の引数の意味 (with-time / inactive) が変わると
brainium 側の orglint が落ちる。"
  (should (equal '(0 . 1) (func-arity 'org-id-new)))
  (should (string-match-p "\\`\\[.*\\]\\'" (org-time-stamp-format t t))))

(ert-deftest warashi-pkm-capture-contract-test-json ()
  "JSON の読み書きが alist / list で行き来できる。"
  (should (equal '((a . 1)) (with-temp-buffer
                              (insert "{\"a\":1}")
                              (goto-char (point-min))
                              (json-parse-buffer :object-type 'alist :array-type 'list))))
  (should (equal "{\"a\":1}" (json-serialize '((a . 1))))))

(ert-deftest warashi-pkm-capture-contract-test-url ()
  "同期リクエストと、let で効かせるリクエスト変数の口が変わっていない。
応答側の `url-http-response-status' と `url-http-end-of-headers' は検証し
ない。url-http がこれらを defvar せずバッファローカルに setq するだけなの
で、実際に通信するまで存在を確かめる術が無い。本体側で `defvar' を書き足
しているのはそのためで、ここで同じ宣言を置いても自分の宣言を見るだけにな
る。"
  (should (equal '(1 . 4) (func-arity 'url-retrieve-synchronously)))
  (should (special-variable-p 'url-request-method))
  (should (special-variable-p 'url-request-data)))

(provide 'warashi-pkm-capture-contract-test)
;;; warashi-pkm-capture-contract-test.el ends here

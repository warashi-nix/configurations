;;; warashi-nskk-marker-test.el --- マーカー操作のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-nskk-marker-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nskk)
(require 'warashi-nskk-marker)

(defun warashi-nskk-marker-test--record-changes ()
  "このバッファの変更を記録し、記録先のシンボルを返す。"
  (let ((changes (make-symbol "changes")))
    (set changes nil)
    (add-hook 'after-change-functions
              (lambda (beg end _len)
                (push (buffer-substring-no-properties beg end)
                      (symbol-value changes)))
              nil t)
    changes))

;;;; 挿入

(ert-deftest warashi-nskk-marker-test-insert-is-visible-to-hooks ()
  "マーカーの挿入は after-change-functions に見える。
隠れた挿入でバッファの位置がずれると、次の通常の挿入で track-changes の整合
検査が落ち、copilot が差分を追わなくなる。"
  (with-temp-buffer
    (let ((changes (warashi-nskk-marker-test--record-changes)))
      (warashi-nskk-marker-insert "▽")
      (should (equal '("▽") (symbol-value changes)))
      (should (equal "▽" (buffer-string))))))

;;;; 削除

(ert-deftest warashi-nskk-marker-test-delete-at ()
  "指定位置のマーカーだけを消し、point は動かさない。"
  (with-temp-buffer
    (insert "▽かんじ")
    (goto-char (point-max))
    (warashi-nskk-marker-delete-at (point-min) "▽")
    (should (equal "かんじ" (buffer-string)))
    (should (= (point) (point-max)))))

(ert-deftest warashi-nskk-marker-test-delete-at-no-match ()
  "マーカーが無い位置では何もしない。"
  (with-temp-buffer
    (insert "かんじ")
    (warashi-nskk-marker-delete-at (point-min) "▽")
    (should (equal "かんじ" (buffer-string)))))

;;;; 置き換え

(ert-deftest warashi-nskk-marker-test-replace-at ()
  "▽ から ▼ への置き換えも変更フックに見える。"
  (with-temp-buffer
    (insert "▽かんじ")
    (let ((changes (warashi-nskk-marker-test--record-changes)))
      (warashi-nskk-marker-replace-at (point-min) "▽" "▼")
      (should (equal "▼かんじ" (buffer-string)))
      (should (member "▼" (symbol-value changes))))))

(ert-deftest warashi-nskk-marker-test-replace-at-no-match ()
  "一致しなければ置き換えない。"
  (with-temp-buffer
    (insert "▼かんじ")
    (warashi-nskk-marker-replace-at (point-min) "▽" "▼")
    (should (equal "▼かんじ" (buffer-string)))))

;;;; 差し替え

(ert-deftest warashi-nskk-marker-test-install-advice ()
  "nskk のマーカー操作を全て差し替える。"
  (let ((installed nil))
    (cl-letf (((symbol-function 'advice-add)
               (lambda (fn how advice) (push (cons fn advice) installed))))
      (warashi-nskk-marker-install-advice))
    (should (equal (cons 'nskk-insert-marker #'warashi-nskk-marker-insert)
                   (assq 'nskk-insert-marker installed)))
    (should (equal (cons 'nskk--delete-marker-at #'warashi-nskk-marker-delete-at)
                   (assq 'nskk--delete-marker-at installed)))
    (should (equal (cons 'nskk--replace-marker-at #'warashi-nskk-marker-replace-at)
                   (assq 'nskk--replace-marker-at installed)))
    ;; nskk 側で改名や削除があったときに気付けるようにする。
    (dolist (fn '(nskk-insert-marker nskk--delete-marker-at nskk--replace-marker-at))
      (should (fboundp fn)))))

(provide 'warashi-nskk-marker-test)
;;; warashi-nskk-marker-test.el ends here

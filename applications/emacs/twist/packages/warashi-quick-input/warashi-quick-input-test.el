;;; warashi-quick-input-test.el --- クイック入力のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-quick-input-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'warashi-quick-input)

(defmacro warashi-quick-input-test--with-file (contents &rest body)
  "CONTENTS を書いた .quick-input ファイルを開いたバッファで BODY を評価する。
BODY の後のファイルの中身と、`server-edit' が呼ばれた回数を (CONTENTS . COUNT)
で返す。"
  (declare (indent 1))
  `(let ((file (make-temp-file "warashi-quick-input-test" nil ".quick-input" ,contents))
         (server-edits 0))
     (unwind-protect
         (cl-letf (((symbol-function 'server-edit)
                    (lambda (&rest _) (setq server-edits (1+ server-edits)))))
           (with-current-buffer (find-file-noselect file)
             (unwind-protect
                 (progn ,@body)
               (set-buffer-modified-p nil)
               (kill-buffer)))
           (cons (with-temp-buffer
                   (insert-file-contents file)
                   (buffer-string))
                 server-edits))
       (delete-file file))))

(ert-deftest warashi-quick-input-test-mode-for-quick-input-files ()
  ".quick-input のファイルはクイック入力のモードで開く。"
  (warashi-quick-input-test--with-file ""
    (should (eq major-mode 'warashi-quick-input-mode))))

(ert-deftest warashi-quick-input-test-finish-saves-and-returns-to-client ()
  "確定すると書いた内容をファイルに残し、emacsclient に制御を返す。"
  (should (equal '("こんにちは" . 1)
                 (warashi-quick-input-test--with-file ""
                   (insert "こんにちは")
                   (warashi-quick-input-finish)))))

(ert-deftest warashi-quick-input-test-abort-empties-and-returns-to-client ()
  "中断するとファイルを空にし、emacsclient に制御を返す。"
  (should (equal '("" . 1)
                 (warashi-quick-input-test--with-file "前の内容"
                   (insert "こんにちは")
                   (warashi-quick-input-abort)))))

(ert-deftest warashi-quick-input-test-keys ()
  "C-c C-c で確定し、C-c C-k で中断する。"
  (should (eq #'warashi-quick-input-finish
              (keymap-lookup warashi-quick-input-mode-map "C-c C-c")))
  (should (eq #'warashi-quick-input-abort
              (keymap-lookup warashi-quick-input-mode-map "C-c C-k"))))

;;; warashi-quick-input-test.el ends here

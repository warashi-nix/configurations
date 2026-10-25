;;; warashi-attach-layout-test.el --- attach 時の画面構成の復元のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-attach-layout-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'seq)
(require 'tab-bar)
(require 'warashi-attach-layout)

(defmacro warashi-attach-layout-test--with-client (files &rest body)
  "FILES を開く emacsclient が作ったフレームとして選択中のフレームを扱う。
FILES が nil なら、ファイルを渡さない attach。BODY の後に、フレームの
タブとウィンドウ構成、保存した構成を元に戻す。"
  (declare (indent 1))
  `(let ((frame (selected-frame))
         (client (make-pipe-process :name "warashi-attach-layout-test"))
         (warashi-attach-layout--saved nil))
     (process-put client 'buffers ,files)
     (set-frame-parameter frame 'client client)
     (unwind-protect
         (progn ,@body)
       (delete-process client)
       (set-frame-parameter frame 'client nil)
       (set-frame-parameter frame 'warashi-attach-layout nil)
       (set-frame-parameter frame 'tabs nil)
       (delete-other-windows)
       (switch-to-buffer "*scratch*"))))

(defun warashi-attach-layout-test--arrange ()
  "2 つのタブを作る。1 つ目は 2 分割、2 つ目は名前を付けた単一ウィンドウ。"
  (switch-to-buffer "*first*")
  (split-window-right)
  (other-window 1)
  (switch-to-buffer "*second*")
  (tab-bar-new-tab)
  (tab-bar-rename-tab "other")
  (switch-to-buffer "*third*")
  (tab-bar-select-tab 1))

(defun warashi-attach-layout-test--describe ()
  "選択中のフレームのタブ名とウィンドウのバッファ名を返す。"
  (let ((tabs (funcall tab-bar-tabs-function)))
    (list (mapcar (lambda (tab) (alist-get 'name (cdr tab))) tabs)
          (mapcar (lambda (window) (buffer-name (window-buffer window)))
                  (window-list nil 'no-minibuf))
          (tab-bar--current-tab-index))))

(defun warashi-attach-layout-test--scramble ()
  "タブも分割も無い状態にする。"
  (tab-bar-close-other-tabs)
  (delete-other-windows)
  (switch-to-buffer "*scratch*"))

(ert-deftest warashi-attach-layout-test-restores-layout-for-attach-without-files ()
  "ファイルを渡さない attach には、保存したタブとウィンドウの構成を戻す。"
  (warashi-attach-layout-test--with-client nil
    (warashi-attach-layout--resume (selected-frame))
    (warashi-attach-layout-test--arrange)
    (let ((expected (warashi-attach-layout-test--describe)))
      (warashi-attach-layout--save)
      (warashi-attach-layout-test--scramble)
      (warashi-attach-layout--resume (selected-frame))
      (should (equal expected (warashi-attach-layout-test--describe))))))

(ert-deftest warashi-attach-layout-test-keeps-non-current-tab ()
  "現在でないタブも、切り替えた時に保存した構成で開く。"
  (warashi-attach-layout-test--with-client nil
    (warashi-attach-layout--resume (selected-frame))
    (warashi-attach-layout-test--arrange)
    (warashi-attach-layout--save)
    (warashi-attach-layout-test--scramble)
    (warashi-attach-layout--resume (selected-frame))
    (tab-bar-select-tab 2)
    (should (equal '("*third*")
                   (mapcar (lambda (window) (buffer-name (window-buffer window)))
                           (window-list nil 'no-minibuf))))))

(ert-deftest warashi-attach-layout-test-ignores-client-with-files ()
  "ファイルを渡す emacsclient のフレームは、復元も保存もしない。"
  (warashi-attach-layout-test--with-client nil
    (warashi-attach-layout--resume (selected-frame))
    (warashi-attach-layout-test--arrange)
    (warashi-attach-layout--save)
    (warashi-attach-layout-test--scramble))
  (warashi-attach-layout-test--with-client '(file)
    (let ((warashi-attach-layout--saved '(saved))
          (before (warashi-attach-layout-test--describe)))
      (warashi-attach-layout--resume (selected-frame))
      (should (equal before (warashi-attach-layout-test--describe)))
      (warashi-attach-layout--save)
      (should (equal '(saved) warashi-attach-layout--saved)))))

(ert-deftest warashi-attach-layout-test-mode-hooks-attach-and-changes ()
  "モードは attach とウィンドウ構成の変化に結び付く。"
  (unwind-protect
      (progn
        (warashi-attach-layout-mode 1)
        (should (memq #'warashi-attach-layout--resume-selected server-after-make-frame-hook))
        (should (memq #'warashi-attach-layout--save window-state-change-hook))
        (warashi-attach-layout-mode -1)
        (should-not (memq #'warashi-attach-layout--resume-selected server-after-make-frame-hook))
        (should-not (memq #'warashi-attach-layout--save window-state-change-hook)))
    (warashi-attach-layout-mode -1)))

(provide 'warashi-attach-layout-test)
;;; warashi-attach-layout-test.el ends here

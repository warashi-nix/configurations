;;; warashi-chelly-workspace-test.el --- 専用作業領域のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-chelly-workspace-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'warashi-chelly-workspace)

(defmacro warashi-chelly-workspace-test--with-root (root &rest body)
  "一時ディレクトリを root にして BODY を実行し、後で消す。
ROOT はその一時ディレクトリを束縛する変数名。"
  (declare (indent 1))
  `(let* ((,root (make-temp-file "chelly-workspace-" t))
          (warashi-chelly-workspace-root ,root))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,root t))))

(ert-deftest warashi-chelly-workspace-test-parse-clone ()
  "root 直下の 2 段目だけを clone と見て (repo . name) を返す。"
  (warashi-chelly-workspace-test--with-root root
    (let ((clone (expand-file-name "configurations/main" root)))
      (make-directory (expand-file-name "sub" clone) t)
      (should (equal '("configurations" . "main")
                     (warashi-chelly-workspace-parse clone)))
      (should (equal '("configurations" . "main")
                     (warashi-chelly-workspace-parse (file-name-as-directory clone))))
      ;; 1 段目は repo 名の置き場で clone ではない。
      (should-not (warashi-chelly-workspace-parse
                   (expand-file-name "configurations" root)))
      ;; clone の下のディレクトリも clone ではない。
      (should-not (warashi-chelly-workspace-parse
                   (expand-file-name "sub" clone)))
      (should-not (warashi-chelly-workspace-parse root)))))

(ert-deftest warashi-chelly-workspace-test-parse-outside ()
  "専用領域の外やリモートでは nil。"
  (warashi-chelly-workspace-test--with-root root
    (let ((outside (make-temp-file "chelly-outside-" t)))
      (unwind-protect
          (progn
            (make-directory (expand-file-name "configurations/main" outside) t)
            (should-not (warashi-chelly-workspace-parse
                         (expand-file-name "configurations/main" outside))))
        (delete-directory outside t)))
    (should-not (warashi-chelly-workspace-parse
                 "/ssh:workbench:/srv/chelly-workspaces/configurations/main/"))))

(ert-deftest warashi-chelly-workspace-test-parse-resolves-symlink ()
  "root や clone への symlink 経由でも実体で判定する。"
  (warashi-chelly-workspace-test--with-root root
    (let ((link (concat (make-temp-file "chelly-link-") "-dir")))
      (make-directory (expand-file-name "configurations/main" root) t)
      (make-symbolic-link root link)
      (unwind-protect
          (should (equal '("configurations" . "main")
                         (warashi-chelly-workspace-parse
                          (expand-file-name "configurations/main" link))))
        (delete-file link)))))

(provide 'warashi-chelly-workspace-test)
;;; warashi-chelly-workspace-test.el ends here

;;; warashi-chelly-handoff-test.el --- Magit からの chelly-handoff のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-chelly-handoff-test.el \
;;     -f ert-run-tests-batch-and-exit
;;
;; テストの sandbox には git が無いので、git の出力は固定の行で与え、
;; chelly-handoff の起動は `magit-start-process' を差し替えて記録する。

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'warashi-chelly-handoff)

(defconst warashi-chelly-handoff-test--repository "/home/me/ghq/github.com/Warashi/brainium/"
  "本人の repository の toplevel。")

(defconst warashi-chelly-handoff-test--config
  '("remote.handoff-brainium.chelly-base 1111111111111111111111111111111111111111"
    "remote.handoff-v1.2.chelly-base 2222222222222222222222222222222222222222")
  "`git config --get-regexp' が返す chelly-base の行。")

(defvar warashi-chelly-handoff-test--started nil
  "差し替えた `magit-start-process' の呼び出し。(default-directory program . args) を積む。")

(defmacro warashi-chelly-handoff-test--with-repository (config &rest body)
  "chelly-base の行が CONFIG の repository で BODY を実行する。
chelly-handoff の起動は `warashi-chelly-handoff-test--started' に積むだけにする。"
  (declare (indent 1))
  `(let ((warashi-chelly-handoff-test--started nil)
         (default-directory warashi-chelly-handoff-test--repository))
     (cl-letf (((symbol-function 'warashi-chelly-workspace-available-p) (lambda () t))
               ((symbol-function 'magit-toplevel)
                (lambda (&rest _) warashi-chelly-handoff-test--repository))
               ((symbol-function 'magit-git-lines)
                (lambda (&rest args)
                  (if (equal (car args) "config") ,config
                    (ert-fail (format "unexpected git %S" args)))))
               ((symbol-function 'magit-start-process)
                (lambda (program _input &rest args)
                  (push (cons default-directory (cons program args))
                        warashi-chelly-handoff-test--started)
                  nil)))
       ,@body)))

;;;; handoff 名の列挙

(ert-deftest warashi-chelly-handoff-test-names-from-config ()
  "chelly-base を持つ remote handoff-NAME の NAME を並べる。NAME は '.' を含んでよい。"
  (should (equal '("brainium" "v1.2")
                 (warashi-chelly-handoff--parse-names warashi-chelly-handoff-test--config)))
  (should-not (warashi-chelly-handoff--parse-names nil)))

(ert-deftest warashi-chelly-handoff-test-read-name-single ()
  "handoff が一つなら聞かずにそれを使う。"
  (warashi-chelly-handoff-test--with-repository
      (list (car warashi-chelly-handoff-test--config))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (ert-fail "prompted"))))
      (should (equal "brainium" (warashi-chelly-handoff--read-name "Fetch"))))))

(ert-deftest warashi-chelly-handoff-test-read-name-multiple ()
  "handoff が複数なら既存の名前から選ばせる。"
  (warashi-chelly-handoff-test--with-repository warashi-chelly-handoff-test--config
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt collection &optional _predicate require-match &rest _)
                 (should (equal '("brainium" "v1.2") collection))
                 (should require-match)
                 "v1.2")))
      (should (equal "v1.2" (warashi-chelly-handoff--read-name "Fetch"))))))

(ert-deftest warashi-chelly-handoff-test-read-name-none ()
  "handoff が無い repository では user-error。"
  (warashi-chelly-handoff-test--with-repository nil
    (should-error (warashi-chelly-handoff--read-name "Fetch") :type 'user-error)))

;;;; fetch と update

(ert-deftest warashi-chelly-handoff-test-fetch-and-update-run-in-toplevel ()
  "fetch と update は本人の repository の toplevel で chelly-handoff を起動する。"
  (warashi-chelly-handoff-test--with-repository warashi-chelly-handoff-test--config
    (let ((default-directory (concat warashi-chelly-handoff-test--repository "notes/")))
      (warashi-chelly-handoff-fetch "brainium")
      (warashi-chelly-handoff-update "v1.2"))
    (should (equal `((,warashi-chelly-handoff-test--repository "chelly-handoff" "update" "v1.2")
                     (,warashi-chelly-handoff-test--repository "chelly-handoff" "fetch" "brainium"))
                   warashi-chelly-handoff-test--started))))

(ert-deftest warashi-chelly-handoff-test-refuses-without-handoff ()
  "chelly-handoff か専用領域の無いホストとリモートの repository では起動しない。"
  (warashi-chelly-handoff-test--with-repository warashi-chelly-handoff-test--config
    (cl-letf (((symbol-function 'warashi-chelly-workspace-available-p) (lambda () nil)))
      (should-error (warashi-chelly-handoff-fetch "brainium") :type 'user-error))
    (let ((default-directory "/ssh:host:/home/me/brainium/"))
      (should-error (warashi-chelly-handoff-update "brainium") :type 'user-error))
    (should-not warashi-chelly-handoff-test--started)))

;;;; fetch の後の log

(ert-deftest warashi-chelly-handoff-test-log-range ()
  "受け取った ref が一つなら base からその ref までを範囲にする。"
  (should (equal "1111111..handoff-brainium/feat"
                 (warashi-chelly-handoff--log-range "1111111" '("handoff-brainium/feat"))))
  (should-not (warashi-chelly-handoff--log-range "1111111" nil))
  (should-not (warashi-chelly-handoff--log-range nil '("handoff-brainium/feat")))
  (should-not (warashi-chelly-handoff--log-range
               "1111111" '("handoff-brainium/feat" "handoff-brainium/main"))))

(defmacro warashi-chelly-handoff-test--after-fetch (status &rest body)
  "fetch が STATUS で終わった後の処理を走らせ、開いた log と process buffer を記録して BODY を実行する。"
  (declare (indent 1))
  `(let ((logged nil)
         (process-shown nil)
         (default-directory warashi-chelly-handoff-test--repository))
     (cl-letf (((symbol-function 'magit-get)
                (lambda (&rest keys)
                  (should (equal '("remote" "handoff-brainium" "chelly-base") keys))
                  "1111111"))
               ((symbol-function 'magit-git-lines)
                (lambda (&rest args)
                  (should (equal "for-each-ref" (car args)))
                  (should (equal "refs/remotes/handoff-brainium/" (car (last args))))
                  '("handoff-brainium/feat")))
               ((symbol-function 'magit-log-arguments) (lambda (&rest _) '(("-n256") nil)))
               ((symbol-function 'magit-log-setup-buffer)
                (lambda (revs args files) (setq logged (list revs args files))))
               ((symbol-function 'magit-process-buffer)
                (lambda (&rest _) (setq process-shown t))))
       (warashi-chelly-handoff--after-fetch "brainium" ,status)
       ,@body)))

(ert-deftest warashi-chelly-handoff-test-after-fetch-opens-log ()
  "fetch に成功したら受け取った範囲の log を開く。"
  (warashi-chelly-handoff-test--after-fetch 0
    (should (equal '(("1111111..handoff-brainium/feat") ("-n256") nil) logged))
    (should-not process-shown)))

(ert-deftest warashi-chelly-handoff-test-after-fetch-shows-findings ()
  "新規追跡ファイルの検査で見つかっても ref は受け取っているので、log と検査結果の両方を見せる。"
  (warashi-chelly-handoff-test--after-fetch 1
    (should (equal '(("1111111..handoff-brainium/feat") ("-n256") nil) logged))
    (should process-shown)))

(ert-deftest warashi-chelly-handoff-test-after-fetch-failure ()
  "受け取りそのものが失敗したら log は開かない。"
  (warashi-chelly-handoff-test--after-fetch 2
    (should-not logged)))

;;;; 入口

(ert-deftest warashi-chelly-handoff-test-install ()
  "Magit の buffer と `magit-dispatch' の \"@\" で開ける。"
  (warashi-chelly-handoff-install)
  (should (eq 'warashi-chelly-handoff (keymap-lookup magit-mode-map "@")))
  (should (eq 'warashi-chelly-handoff
              (plist-get (cdr (transient-get-suffix 'magit-dispatch "@")) :command))))

(provide 'warashi-chelly-handoff-test)
;;; warashi-chelly-handoff-test.el ends here

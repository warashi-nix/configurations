;;; warashi-nskk-sticky-test.el --- ▼ 中のセミコロンのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-nskk-sticky-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nskk)
(require 'warashi-nskk-sticky)

(defvar warashi-nskk-sticky-test--calls nil
  "横取り経路で呼ばれた nskk の関数。")

(defmacro warashi-nskk-sticky-test--with-nskk (needed &rest body)
  "implicit kakutei の要否を NEEDED にして BODY を実行する。"
  (declare (indent 1))
  `(let ((warashi-nskk-sticky-test--calls nil)
         (nskk--sticky-shift-pending nil))
     (cl-letf (((symbol-function 'nskk--implicit-kakutei-needed-p)
                (lambda () ,needed))
               ((symbol-function 'nskk-commit-current)
                (lambda (&rest _) (push 'commit warashi-nskk-sticky-test--calls)))
               ((symbol-function 'nskk--setup-henkan-start-marker)
                (lambda (char) (push (cons 'marker char)
                                     warashi-nskk-sticky-test--calls))))
       ,@body)))

(ert-deftest warashi-nskk-sticky-test-restarts-henkan ()
  "▼ 中の ; は確定してから次の見出しを開く。"
  (warashi-nskk-sticky-test--with-nskk t
    (let ((fell-through nil))
      (should (warashi-nskk-sticky-restart-henkan (lambda () (setq fell-through t))))
      ;; 本体の処理には流さない。流すと ; がそのまま挿入されて 初回;こうぎ になる。
      (should-not fell-through)
      (should (equal (list (cons 'marker ?\;) 'commit)
                     warashi-nskk-sticky-test--calls))
      ;; 開いた見出しに続く打鍵を送るため、sticky を pending にして返す。
      (should (eq 'immediate nskk--sticky-shift-pending)))))

(ert-deftest warashi-nskk-sticky-test-falls-through-when-not-needed ()
  "確定が要らない場面 (送り仮名の途中や候補一覧) は本体に任せる。"
  (warashi-nskk-sticky-test--with-nskk nil
    (let ((fell-through nil))
      (warashi-nskk-sticky-restart-henkan (lambda () (setq fell-through t)))
      (should fell-through)
      (should-not warashi-nskk-sticky-test--calls))))

(ert-deftest warashi-nskk-sticky-test-falls-through-when-pending ()
  "sticky が pending のときは横取りしない。
;; の取り消し (Arm 1) を先に通さないと、二重セミコロンでリテラルの ; が
出せなくなる。"
  (warashi-nskk-sticky-test--with-nskk t
    (setq nskk--sticky-shift-pending 'immediate)
    (let ((fell-through nil))
      (warashi-nskk-sticky-restart-henkan (lambda () (setq fell-through t)))
      (should fell-through)
      (should-not warashi-nskk-sticky-test--calls))))

(ert-deftest warashi-nskk-sticky-test-install-advice ()
  "nskk の sticky shift ディスパッチに足す。"
  (let ((installed nil))
    (cl-letf (((symbol-function 'advice-add)
               (lambda (fn how advice) (push (list fn how advice) installed))))
      (warashi-nskk-sticky-install-advice))
    (should (equal (list (list 'nskk--sticky-shift-dispatch :around
                               #'warashi-nskk-sticky-restart-henkan))
                   installed))
    ;; nskk 側で改名や削除があったときに気付けるようにする。
    (dolist (fn '(nskk--sticky-shift-dispatch nskk--implicit-kakutei-needed-p
                  nskk-commit-current nskk--setup-henkan-start-marker))
      (should (fboundp fn)))))

(provide 'warashi-nskk-sticky-test)
;;; warashi-nskk-sticky-test.el ends here

;;; warashi-pkm-capture-test.el --- モバイル capture 取り込みのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-pkm-capture-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'warashi-pkm-capture)

(defvar warashi-pkm-capture-test--requests nil
  "テスト中に投げた要求。(METHOD PATH PAYLOAD) のリスト。")

(defvar warashi-pkm-capture-test--pending nil
  "queue に溜まっている capture。")

(defvar warashi-pkm-capture-test--lint-status 0
  "orglint の終了ステータス。")

(defmacro warashi-pkm-capture-test--with-inbox (&rest body)
  "空の inbox.org と stub した n8n / orglint を用意して BODY を実行する。"
  (declare (indent 0))
  `(let* ((dir (make-temp-file "warashi-pkm-capture-test" t))
          (warashi-pkm-capture-inbox-file (file-name-concat dir "inbox.org"))
          (warashi-pkm-capture-orglint-command '("orglint"))
          (warashi-pkm-capture--unacked nil)
          (warashi-pkm-capture-test--requests nil)
          (warashi-pkm-capture-test--lint-status 0)
          (org-id-method 'ts))
     (write-region "" nil warashi-pkm-capture-inbox-file)
     (cl-letf (((symbol-function 'warashi-pkm-capture--request)
                (lambda (method path &optional payload)
                  (push (list method path payload) warashi-pkm-capture-test--requests)
                  (when (equal path "/pending")
                    `((items . ,warashi-pkm-capture-test--pending)))))
               ((symbol-function 'call-process)
                (lambda (&rest _) warashi-pkm-capture-test--lint-status))
               ((symbol-function 'display-buffer) #'ignore))
       (unwind-protect (progn ,@body)
         (when-let* ((buffer (find-buffer-visiting warashi-pkm-capture-inbox-file)))
           (kill-buffer buffer))
         (delete-directory dir t)))))

(defun warashi-pkm-capture-test--inbox ()
  "inbox.org の中身を返す。"
  (with-temp-buffer
    (insert-file-contents warashi-pkm-capture-inbox-file)
    (buffer-string)))

;;;; org への変換

(defconst warashi-pkm-capture-test--created-at "2026-08-25T12:34:00+09:00"
  "テストに使う capture の作成時刻。")

(defun warashi-pkm-capture-test--to-org (text &optional id)
  "TEXT と ID から変換結果を返す。作成時刻は固定。"
  (warashi-pkm-capture--to-org
   `((text . ,text) (createdAt . ,warashi-pkm-capture-test--created-at))
   id))

(defun warashi-pkm-capture-test--without-captured (entry)
  "ENTRY から CAPTURED の行を落とす。表記は locale と時間帯で変わるため。"
  (replace-regexp-in-string "^:CAPTURED:.*\n" "" entry))

(ert-deftest warashi-pkm-capture-test-to-org-single-line ()
  "1 行の capture は見出しだけになる。"
  (should (equal (concat "* 買い物\n"
                         ":PROPERTIES:\n"
                         ":ID: abc\n"
                         ":END:\n")
                 (warashi-pkm-capture-test--without-captured
                  (warashi-pkm-capture-test--to-org "買い物" "abc")))))

(ert-deftest warashi-pkm-capture-test-to-org-multi-line ()
  "2 行目以降は本文として見出しの下に置く。"
  (should (equal (concat "* 買い物\n"
                         ":PROPERTIES:\n"
                         ":ID: abc\n"
                         ":END:\n"
                         "牛乳\n卵\n")
                 (warashi-pkm-capture-test--without-captured
                  (warashi-pkm-capture-test--to-org "買い物\n牛乳\n卵" "abc")))))

(ert-deftest warashi-pkm-capture-test-to-org-captured-time ()
  "CAPTURED は capture した瞬間を指す。"
  (let* ((entry (warashi-pkm-capture-test--to-org "買い物" "abc"))
         (stamp (progn (string-match "^:CAPTURED: \\(.*\\)$" entry)
                       (match-string 1 entry))))
    (should (time-equal-p
             (encode-time (iso8601-parse warashi-pkm-capture-test--created-at))
             (org-time-string-to-time stamp)))
    ;; 時刻付きの非アクティブなスタンプにする。アクティブだと agenda に出る。
    (should (string-prefix-p "[" stamp))
    (should (string-match-p "[0-9][0-9]:[0-9][0-9]\\]\\'" stamp))))

(ert-deftest warashi-pkm-capture-test-to-org-trims ()
  "前後の空白と末尾の空行は落とす。org の構造が崩れるため。"
  (should (equal (warashi-pkm-capture-test--to-org "買い物\n牛乳" "abc")
                 (warashi-pkm-capture-test--to-org "\n 買い物\n牛乳\n\n " "abc"))))

(ert-deftest warashi-pkm-capture-test-to-org-generates-id ()
  "ID を渡さなければ採番する。"
  (let ((org-id-method 'uuid))
    (should (string-match-p ":ID: [0-9a-f-]+\n"
                            (warashi-pkm-capture-test--to-org "x")))))

;;;; 同期

(ert-deftest warashi-pkm-capture-test-sync-appends ()
  "取り込んだ capture を inbox.org の末尾に足し、id を ack する。"
  (let ((warashi-pkm-capture-test--pending
         '(((id . "1") (text . "一件目") (createdAt . "2026-08-25T12:34:00+09:00"))
           ((id . "2") (text . "二件目") (createdAt . "2026-08-25T12:35:00+09:00")))))
    (warashi-pkm-capture-test--with-inbox
      (warashi-pkm-capture-sync)
      (let ((inbox (warashi-pkm-capture-test--inbox)))
        (should (string-match-p "^\\* 一件目$" inbox))
        (should (string-match-p "^\\* 二件目$" inbox)))
      (should (equal '("POST" "/ack" ((ids . ["1" "2"])))
                     (car warashi-pkm-capture-test--requests)))
      ;; ack が通ったら控えは空にする。次の同期で二重に ack しないため。
      (should-not warashi-pkm-capture--unacked))))

(ert-deftest warashi-pkm-capture-test-sync-empty ()
  "queue が空なら inbox.org には触らない。"
  (let ((warashi-pkm-capture-test--pending nil))
    (warashi-pkm-capture-test--with-inbox
      (warashi-pkm-capture-sync)
      (should (equal "" (warashi-pkm-capture-test--inbox)))
      (should (equal '(("GET" "/pending" nil)) warashi-pkm-capture-test--requests)))))

(ert-deftest warashi-pkm-capture-test-sync-keeps-entries-on-lint-failure ()
  "orglint が通らなくても取り込みは残し、ack もする。
巻き戻すと手で直す機会が無く、ack しないと次の同期で二重に入る。"
  (let ((warashi-pkm-capture-test--pending
         '(((id . "1") (text . "壊れた capture")
            (createdAt . "2026-08-25T12:34:00+09:00")))))
    (warashi-pkm-capture-test--with-inbox
      (setq warashi-pkm-capture-test--lint-status 1)
      (warashi-pkm-capture-sync)
      (should (string-match-p "^\\* 壊れた capture$" (warashi-pkm-capture-test--inbox)))
      (should-not warashi-pkm-capture--unacked)
      (should (equal '("POST" "/ack" ((ids . ["1"])))
                     (car warashi-pkm-capture-test--requests))))))

(ert-deftest warashi-pkm-capture-test-sync-keeps-existing-entries ()
  "既にある内容の後ろに足す。行頭でなければ改行を挟む。"
  (let ((warashi-pkm-capture-test--pending
         '(((id . "1") (text . "追記") (createdAt . "2026-08-25T12:34:00+09:00")))))
    (warashi-pkm-capture-test--with-inbox
      (write-region "* 既存" nil warashi-pkm-capture-inbox-file)
      (warashi-pkm-capture-sync)
      (should (string-prefix-p "* 既存\n* 追記\n" (warashi-pkm-capture-test--inbox))))))

;;;; ack のやり直し

(ert-deftest warashi-pkm-capture-test-ack-retries-unacked ()
  "ack しそこねた id は次の同期の先頭で送り直す。"
  (let ((warashi-pkm-capture-test--pending nil))
    (warashi-pkm-capture-test--with-inbox
      (setq warashi-pkm-capture--unacked '("9"))
      (warashi-pkm-capture-sync)
      (should (equal '("POST" "/ack" ((ids . ["9"])))
                     (car (last warashi-pkm-capture-test--requests))))
      (should-not warashi-pkm-capture--unacked))))

(ert-deftest warashi-pkm-capture-test-ack-without-unacked ()
  "控えが無ければ ack は投げない。"
  (warashi-pkm-capture-test--with-inbox
    (warashi-pkm-capture--ack)
    (should-not warashi-pkm-capture-test--requests)))

(provide 'warashi-pkm-capture-test)
;;; warashi-pkm-capture-test.el ends here

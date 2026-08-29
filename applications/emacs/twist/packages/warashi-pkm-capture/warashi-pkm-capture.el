;;; warashi-pkm-capture.el --- モバイル capture を inbox.org へ取り込む  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: outlines, convenience

;;; Commentary:

;; スマホからの capture は n8n の pending queue に溜まる。`warashi-pkm-capture-sync'
;; で pull し、inbox.org へ追記してから ack する。追記した内容には orglint -fix を
;; かけ、直らない違反が残っても警告するだけで取り込みは通す。org 書式を組み
;; 立てるのは Emacs のこの 1 箇所だけで、n8n は text をそのまま預かる。
;;
;; consumer token は pull と ack ができてしまうため、iOS ショートカットが持つ
;; producer token とは別のものを SOPS 経由でファイルに置き、その内容を
;; Authorization ヘッダーにそのまま使う。
;;
;; 利用側で `warashi-pkm-capture-inbox-file' と
;; `warashi-pkm-capture-orglint-command' を PKM の場所から導出して設定する。

;;; Code:

;; url-request-* を let で効かせるにも、応答のバッファローカル変数を読むにも
;; url-http がロード済みである必要がある。
(require 'url-http)
(require 'iso8601)
(require 'org-id)

;; url-http がバッファローカルに設定する変数。byte-compile に特殊変数だと
;; 教えるためだけの宣言。
(defvar url-http-response-status)
(defvar url-http-end-of-headers)

(defcustom warashi-pkm-capture-endpoint
  "https://n8n.warashi.dev/webhook/mobile-capture"
  "モバイル capture の queue を提供する n8n webhook のベース URL。"
  :type 'string
  :group 'org)

(defcustom warashi-pkm-capture-token-file
  (file-name-concat (or (getenv "XDG_CONFIG_HOME") "~/.config")
                    "mobile-capture/consumer-token")
  "consumer 用の Authorization ヘッダー値を収めたファイル。"
  :type 'file
  :group 'org)

(defcustom warashi-pkm-capture-inbox-file nil
  "取り込み先の inbox.org。"
  :type '(choice (const nil) file)
  :group 'org)

(defcustom warashi-pkm-capture-orglint-command nil
  "取り込んだ内容に orglint をかけるコマンドと引数。"
  :type '(repeat string)
  :group 'org)

(defvar warashi-pkm-capture--unacked nil
  "ack しそこねた capture の id。次の同期の先頭で送り直す。")

(defun warashi-pkm-capture--request (method path &optional payload)
  "n8n の PATH へ METHOD で要求を出し、応答の JSON を alist で返す。
PAYLOAD が非 nil ならそれを JSON の body として送る。"
  (let* ((url-request-method method)
         (url-request-data
          (when payload (encode-coding-string (json-serialize payload) 'utf-8)))
         (url-request-extra-headers
          (append `(("Authorization"
                     . ,(with-temp-buffer
                          (insert-file-contents warashi-pkm-capture-token-file)
                          (string-trim (buffer-string)))))
                  (when payload '(("Content-Type" . "application/json")))))
         (buffer (url-retrieve-synchronously
                  (concat warashi-pkm-capture-endpoint path) t t 30)))
    (unless buffer
      (error "n8n への %s %s に失敗しました" method path))
    (unwind-protect
        (with-current-buffer buffer
          ;; ヘッダーは自分で探さない。Emacs 29 以降の url-http は CRLF を
          ;; 落とさなくなったため、"\n\n" を探す実装は本文に辿り着けない。
          (unless (and (<= 200 url-http-response-status)
                       (< url-http-response-status 300))
            (error "n8n が %d を返しました (%s %s)"
                   url-http-response-status method path))
          (goto-char url-http-end-of-headers)
          (decode-coding-region (point) (point-max) 'utf-8)
          (json-parse-buffer :object-type 'alist :array-type 'list))
      (kill-buffer buffer))))

(defun warashi-pkm-capture--to-org (capture &optional id)
  "CAPTURE を inbox.org のエントリ 1 件分の文字列にする。
CAPTURE は n8n の queue の 1 行で、text と createdAt を持つ alist。
ID を省略した場合は `org-id-new' で採番する。"
  (let* ((lines (split-string (string-trim (alist-get 'text capture)) "\n"))
         (body (string-trim-right (string-join (cdr lines) "\n"))))
    (concat "* " (car lines) "\n"
            ":PROPERTIES:\n"
            ":ID: " (or id (org-id-new)) "\n"
            ":CAPTURED: "
            (format-time-string
             (org-time-stamp-format t t)
             (encode-time (iso8601-parse (alist-get 'createdAt capture))))
            "\n"
            ":END:\n"
            (if (string-empty-p body) "" (concat body "\n")))))

(defun warashi-pkm-capture--ack ()
  "`warashi-pkm-capture--unacked' の id を n8n の queue から消す。"
  (when warashi-pkm-capture--unacked
    (warashi-pkm-capture--request
     "POST" "/ack" `((ids . ,(vconcat warashi-pkm-capture--unacked))))
    (setq warashi-pkm-capture--unacked nil)))

(defun warashi-pkm-capture-sync ()
  "n8n の queue にあるモバイル capture を inbox.org へ取り込む。"
  (interactive)
  (warashi-pkm-capture--ack)
  (let ((captures
         (alist-get 'items (warashi-pkm-capture--request "GET" "/pending"))))
    (if (null captures)
        (message "取り込む capture はありません")
      (find-file warashi-pkm-capture-inbox-file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (let ((start (point))
            (lint (get-buffer-create "*pkm-orglint*")))
        (dolist (capture captures)
          (insert (warashi-pkm-capture--to-org capture)))
        (save-buffer)
        (with-current-buffer lint (erase-buffer))
        ;; orglint は -fix で直せる分を書き戻してから検査する。直らなかった分は
        ;; 巻き戻さずに残す。巻き戻すと queue から取り直しても同じ場所で落ち、
        ;; 手で直す経路が無くなるため。
        (let ((linted (eq 0 (apply #'call-process
                                   (car warashi-pkm-capture-orglint-command)
                                   nil lint nil
                                   (cdr warashi-pkm-capture-orglint-command)))))
          (revert-buffer t t)
          (goto-char (min start (point-max)))
          (setq warashi-pkm-capture--unacked
                (mapcar (lambda (capture) (alist-get 'id capture)) captures))
          (warashi-pkm-capture--ack)
          (if linted
              (message "%d 件取り込みました" (length captures))
            (display-buffer lint)
            (message "%d 件取り込みましたが orglint が通っていません"
                     (length captures))))))))

(provide 'warashi-pkm-capture)
;;; warashi-pkm-capture.el ends here

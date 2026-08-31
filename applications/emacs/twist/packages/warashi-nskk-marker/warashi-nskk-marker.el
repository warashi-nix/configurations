;;; warashi-nskk-marker.el --- nskk のマーカーを変更フックから隠さない  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (nskk "0.3.0"))
;; Keywords: i18n, japanese, convenience

;;; Commentary:

;; nskk は ▽ ▼ の挿入を `inhibit-modification-hooks' で隠す (`nskk-henkan.el' の
;; `nskk-insert-marker' ほか)。隠れた挿入でバッファの位置がずれるため、次の通常
;; の挿入で track-changes の整合検査が落ちる。K で ▽ が入った時点では無事で、続く
;; a で かな が入った瞬間に死ぬ。
;;
;; 実害は copilot。`after-change-functions' でエラーが出ると Emacs はその関数を
;; hook から外すので、日本語を一文字打ったバッファでは以後 copilot が差分を追わな
;; くなる。copilot-mode は有効に見えたままなので気付けない。
;;
;; マーカーを普通に挿入すれば整合は保たれる。undo にマーカーが入るので C-x u で
;; ▼かんじ → ▽かんじ → ▽かん と打鍵を遡るようになるが、打った手順を巻き戻して
;; いるだけで実害は無い。
;;
;; 利用側で `warashi-nskk-marker-install-advice' を nskk のロード後に呼ぶ。

;;; Code:

(eval-when-compile (require 'nskk))

(defun warashi-nskk-marker-insert (marker)
  "MARKER を変更フックから隠さずに挿入する。"
  (insert marker))

(defun warashi-nskk-marker-delete-at (pos marker-regexp)
  "POS にある MARKER-REGEXP に一致するマーカーを消す。"
  (save-excursion
    (goto-char pos)
    (when (looking-at marker-regexp)
      (delete-char (length (match-string 0))))))

(defun warashi-nskk-marker-replace-at (pos old-regexp new-marker)
  "POS の OLD-REGEXP に一致するマーカーを NEW-MARKER に置き換える。"
  (save-excursion
    (goto-char pos)
    (when (looking-at old-regexp)
      (delete-char (length (match-string 0)))
      (insert new-marker))))

(defun warashi-nskk-marker-install-advice ()
  "nskk のマーカー操作をここの実装に差し替える。"
  (advice-add 'nskk-insert-marker :override #'warashi-nskk-marker-insert)
  (advice-add 'nskk--delete-marker-at :override #'warashi-nskk-marker-delete-at)
  (advice-add 'nskk--replace-marker-at :override #'warashi-nskk-marker-replace-at))

(provide 'warashi-nskk-marker)
;;; warashi-nskk-marker.el ends here

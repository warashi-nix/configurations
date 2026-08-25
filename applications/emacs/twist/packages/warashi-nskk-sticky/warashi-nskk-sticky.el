;;; warashi-nskk-sticky.el --- ▼ 変換中のセミコロンで次の見出しを始める  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (nskk "0.3.0"))
;; Keywords: i18n, japanese, convenience

;;; Commentary:

;; ; の sticky shift は、▼ 変換中 (`nskk--sticky-shift-dispatch' の Arm 2) だけ
;; self-insert に落ちる。;shokai SPC ;kougi SPC と打つと、二つ目の ; がそのまま
;; 挿入されて 初回;こうぎ になる。大文字での ;shokai SPC Kougi は
;; `nskk-self-insert' の implicit kakutei を通って 初回講義 になるので、; だけが
;; この経路から外れている。
;;
;; ▼ の ; も大文字と同じ「確定してから次の見出しを開く」に合流させる。確定する
;; かどうかは自前で判定せず `nskk--implicit-kakutei-needed-p' に委ねるので、送り
;; 仮名の途中や候補一覧が出ている間は従来どおり本体の処理に流れる。
;;
;; 利用側で `warashi-nskk-sticky-install-advice' を nskk のロード後に呼ぶ。

;;; Code:

(eval-when-compile (require 'nskk))

(defun warashi-nskk-sticky-restart-henkan (fn)
  "▼ 変換中の ; を確定して次の見出しに繋ぐ。それ以外は FN に流す。"
  ;; sticky が pending のときは横取りしない。;; の取り消し (Arm 1) を先に
  ;; 通さないと、二重セミコロンでリテラルの ; が出せなくなる。
  (if (and (not nskk--sticky-shift-pending)
           (nskk--implicit-kakutei-needed-p))
      (progn
        (nskk-commit-current)
        (nskk--setup-henkan-start-marker ?\;)
        (setq nskk--sticky-shift-pending 'immediate)
        t)
    (funcall fn)))

(defun warashi-nskk-sticky-install-advice ()
  "nskk の sticky shift のディスパッチにこの経路を足す。"
  (advice-add 'nskk--sticky-shift-dispatch :around
              #'warashi-nskk-sticky-restart-henkan))

(provide 'warashi-nskk-sticky)
;;; warashi-nskk-sticky.el ends here

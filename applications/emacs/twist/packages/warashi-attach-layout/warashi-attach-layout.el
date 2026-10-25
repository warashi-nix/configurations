;;; warashi-attach-layout.el --- emacsclient の attach 時に前回の画面構成へ戻す  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, frames

;;; Commentary:

;; daemon に ファイルを渡さず emacsclient でつないだフレームを「attach」とみなし、
;; 直前の attach で最後に見ていたタブとウィンドウ分割に戻す。daemon が生きている
;; 間だけ覚えていて、ディスクには残さない。
;;
;; フレームが消える時に保存しないのは、SSH の切断のように端末ごと消える detach
;; では、フックが呼ばれた時にはもうフレームが死んでいて読めないため。代わりに
;; ウィンドウ構成が変わるたびに保存する。
;;
;; `frameset-save' を使わないのは、フレームの大きさや位置、クライアントの環境変数まで
;; 保存してしまい、別の端末への復元でそれらを外すフィルタが必要になるため。
;; ファイルを渡すフレーム (quick-input など) は、復元も保存もしない。
;;
;; side window は which-key のポップアップのような一時的な表示で、別のフレームの
;; ルートへ戻すと `window-state-put' が失敗するため、保存の対象から外す。

;;; Code:

(require 'seq)
(require 'tab-bar)

(defvar warashi-attach-layout--saved nil
  "最後に保存した画面構成。(TABS . WINDOW-STATE) か nil。")

(defun warashi-attach-layout--attach-frame-p (frame)
  "FRAME が、ファイルを渡さない emacsclient のフレームなら non-nil。"
  (let ((client (frame-parameter frame 'client)))
    (and (processp client)
         (not (process-get client 'buffers)))))

(defun warashi-attach-layout--save ()
  "選択中のフレームが attach したものなら、その画面構成を保存する。"
  (let ((frame (selected-frame)))
    (when (frame-parameter frame 'warashi-attach-layout)
      (setq warashi-attach-layout--saved
            (cons (mapcar (lambda (tab)
                            ;; 閉じたフレームの window-configuration を抱え続けない。
                            (copy-tree (cons (car tab)
                                             (seq-remove (lambda (entry) (eq (car entry) 'wc))
                                                         (cdr tab)))))
                          (funcall tab-bar-tabs-function frame))
                  (window-state-get (window-main-window frame) 'writable))))))

(defun warashi-attach-layout--resume (frame)
  "FRAME が attach なら、保存した画面構成を戻し、以後の保存の対象にする。
保存の対象にするのは戻した後にする。戻す前の空の構成で上書きしないため。"
  (when (warashi-attach-layout--attach-frame-p frame)
    (when warashi-attach-layout--saved
      (set-frame-parameter frame 'tabs (copy-tree (car warashi-attach-layout--saved)))
      (window-state-put (copy-tree (cdr warashi-attach-layout--saved))
                        (window-main-window frame) 'safe))
    (set-frame-parameter frame 'warashi-attach-layout t)))

(defun warashi-attach-layout--resume-selected ()
  "`server-after-make-frame-hook' 用。作ったばかりのフレームに戻す。"
  (warashi-attach-layout--resume (selected-frame)))

;;;###autoload
(define-minor-mode warashi-attach-layout-mode
  "emacsclient の attach 時に前回の画面構成へ戻す。"
  :global t
  :group 'frames
  (if warashi-attach-layout-mode
      (progn
        (add-hook 'server-after-make-frame-hook #'warashi-attach-layout--resume-selected)
        (add-hook 'window-state-change-hook #'warashi-attach-layout--save))
    (remove-hook 'server-after-make-frame-hook #'warashi-attach-layout--resume-selected)
    (remove-hook 'window-state-change-hook #'warashi-attach-layout--save)))

(provide 'warashi-attach-layout)
;;; warashi-attach-layout.el ends here

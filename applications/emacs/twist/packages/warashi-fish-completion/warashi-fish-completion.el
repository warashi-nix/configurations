;;; warashi-fish-completion.el --- fish-completion の補正  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: processes, completion

;;; Commentary:

;; fish-completion <https://github.com/LemonBreezes/emacs-fish-completion> を
;; corfu-auto と組み合わせたときの問題を、advice で補う。
;;
;; `warashi-fish-completion-install-call' を呼ぶと、fish の呼び出しが
;; 打鍵で中断されても入力を取り零さなくなる。

;;; Code:

(defun warashi-fish-completion--call (command &rest args)
  "COMMAND を ARGS で走らせ、標準出力を文字列で返す。標準エラーは捨てる。"
  ;; call-process ではなく make-process で待つのは、corfu-auto が
  ;; `while-no-input' の中で capf を呼ぶため。call-process の最中に打鍵が
  ;; 来ると中断が quit として扱われ、ベルが鳴って打鍵が捨てられる。
  ;; accept-process-output で待てば、中断は打鍵を残したままの throw になる。
  (let ((stdout (generate-new-buffer " *warashi-fish-completion*" t))
        (stderr (generate-new-buffer " *warashi-fish-completion-stderr*" t)))
    (unwind-protect
        (let ((process (make-process :name "warashi-fish-completion"
                                     :buffer stdout
                                     :stderr stderr
                                     :command (cons command args)
                                     :connection-type 'pipe
                                     :noquery t
                                     :sentinel #'ignore)))
          (unwind-protect
              (while (accept-process-output process))
            (delete-process process))
          (with-current-buffer stdout
            (buffer-string)))
      (kill-buffer stdout)
      (kill-buffer stderr))))

(defun warashi-fish-completion-install-call ()
  "fish の呼び出しを打鍵で中断しても入力を取り零さない形にする。"
  (advice-add 'fish-completion--call :override
              #'warashi-fish-completion--call))

(provide 'warashi-fish-completion)
;;; warashi-fish-completion.el ends here

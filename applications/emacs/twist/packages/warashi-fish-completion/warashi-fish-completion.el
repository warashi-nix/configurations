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
;;
;; `warashi-fish-completion-install-cache' を呼ぶと、同じ引数を打ち進める
;; 間は最後に fish に聞いた結果を使い回し、打鍵ごとに fish を起動しなくなる。

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

;;;; 候補の使い回し

(defvar warashi-fish-completion--cache nil
  "最後に fish に聞いた結果。(DIRECTORY PROMPT . OUTPUT) か nil。")

(defun warashi-fish-completion-clear-cache ()
  "覚えている fish の結果を捨てる。"
  (setq warashi-fish-completion--cache nil))

(defun warashi-fish-completion--reusable-p (cache directory prompt)
  "DIRECTORY で PROMPT を補完するときに CACHE の結果を使えるなら non-nil。
PROMPT が CACHE のプロンプトの最後の引数を打ち進めただけのときに限る。"
  (pcase cache
    (`(,cached-directory ,cached-prompt . ,_)
     (and (equal cached-directory directory)
          (string-prefix-p cached-prompt prompt)
          ;; 引数が空のとき fish はオプションを返さず、- を打って初めて返す。
          ;; 空の引数で聞いた結果は、打ち始めた引数の候補を含むとは限らない。
          (string-match-p "[^[:space:]]\\'" cached-prompt)
          (not (string-match-p "[[:space:]]"
                               (substring prompt (length cached-prompt))))))))

(defun warashi-fish-completion--list-completions-with-desc (orig raw-prompt)
  "RAW-PROMPT の候補を、使い回せるなら覚えた結果から、無理なら ORIG で返す。"
  ;; corfu はポップアップを出している間、打鍵のたびに capf を呼び直す。
  ;; そのたびに fish を起動すると打鍵が遅れる。同じ引数を打ち進める間は
  ;; 候補が前回の結果に含まれ、絞り込みは Emacs 側の補完スタイルが行う。
  (if (warashi-fish-completion--reusable-p warashi-fish-completion--cache
                                           default-directory raw-prompt)
      (cddr warashi-fish-completion--cache)
    (let ((output (funcall orig raw-prompt)))
      (setq warashi-fish-completion--cache
            (cons default-directory (cons raw-prompt output)))
      output)))

(defun warashi-fish-completion-install-cache ()
  "同じ引数を打ち進める間は fish を呼び直さない形にする。
eshell でコマンドを実行するたびに覚えた結果を捨てる。"
  (advice-add 'fish-completion--list-completions-with-desc :around
              #'warashi-fish-completion--list-completions-with-desc)
  (add-hook 'eshell-pre-command-hook #'warashi-fish-completion-clear-cache))

(provide 'warashi-fish-completion)
;;; warashi-fish-completion.el ends here

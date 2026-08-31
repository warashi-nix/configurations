;;; warashi-nskk-cursor-test.el --- カーソル色の同期のテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-nskk-cursor-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nskk)
(require 'warashi-nskk-cursor)

;; 学習データを ~/.emacs.d に書き出させない。保存は kill-emacs-hook でも走るので
;; let 束縛では間に合わない。
(setq nskk-search-learning-file
      (expand-file-name "warashi-nskk-cursor-test-learning.dat" temporary-file-directory))
(setq nskk-study-file
      (expand-file-name "warashi-nskk-cursor-test-study.dat" temporary-file-directory))

(defvar warashi-nskk-cursor-test--sent nil
  "端末へ送った文字列のリスト。")

(defmacro warashi-nskk-cursor-test--with-terminal (&rest body)
  "端末への送信を捕まえ、色を触っていない状態から BODY を実行する。"
  (declare (indent 0))
  `(let ((warashi-nskk-cursor-test--sent nil))
     (set-terminal-parameter nil 'warashi-nskk-cursor-tty-spec nil)
     (cl-letf (((symbol-function 'send-string-to-terminal)
                (lambda (string &rest _)
                  (push string warashi-nskk-cursor-test--sent))))
       (unwind-protect (progn ,@body)
         (set-terminal-parameter nil 'warashi-nskk-cursor-tty-spec nil)))))

(defmacro warashi-nskk-cursor-test--with-frame (&rest body)
  "フレームのカーソル関連パラメータを元に戻しつつ BODY を実行する。"
  (declare (indent 0))
  `(let ((frame (selected-frame)))
     (unwind-protect (progn ,@body)
       (set-frame-parameter frame 'warashi-nskk-cursor-original nil)
       (set-frame-parameter frame 'cursor-color nil))))

;;;; 色の決定

(ert-deftest warashi-nskk-cursor-test-color-without-nskk ()
  "nskk が居ないバッファには色を付けない。"
  (with-temp-buffer
    (should-not (warashi-nskk-cursor-color))))

(ert-deftest warashi-nskk-cursor-test-color-follows-mode ()
  "モードごとに違う色を返す。"
  (with-temp-buffer
    (electric-indent-local-mode -1)
    (nskk-mode 1)
    (unwind-protect
        (let (colors)
          (dolist (mode '(hiragana katakana ascii))
            (nskk-set-mode mode)
            (push (warashi-nskk-cursor-color) colors))
          (should (cl-every #'stringp colors))
          (should (equal colors (cl-remove-duplicates colors :test #'equal))))
      (ignore-errors (nskk-mode -1)))))

;;;; GUI

(ert-deftest warashi-nskk-cursor-test-gui-saves-and-restores ()
  "色を付ける前の値を退避し、nil で元に戻す。"
  (warashi-nskk-cursor-test--with-frame
    (set-frame-parameter frame 'cursor-color "white")
    (warashi-nskk-cursor--apply-gui "red")
    (should (equal "white" (frame-parameter frame 'warashi-nskk-cursor-original)))
    (should (equal "red" (frame-parameter frame 'cursor-color)))
    (warashi-nskk-cursor--apply-gui nil)
    (should (equal "white" (frame-parameter frame 'cursor-color)))
    (should-not (frame-parameter frame 'warashi-nskk-cursor-original))))

(ert-deftest warashi-nskk-cursor-test-gui-keeps-first-original ()
  "続けて色を変えても、退避値は最初の一回だけ取る。"
  (warashi-nskk-cursor-test--with-frame
    (set-frame-parameter frame 'cursor-color "white")
    (warashi-nskk-cursor--apply-gui "red")
    (warashi-nskk-cursor--apply-gui "blue")
    (should (equal "white" (frame-parameter frame 'warashi-nskk-cursor-original)))
    (warashi-nskk-cursor--apply-gui nil)
    (should (equal "white" (frame-parameter frame 'cursor-color)))))

(ert-deftest warashi-nskk-cursor-test-gui-unset-cursor-color ()
  "cursor-color が未設定のフレームでも、元の未設定状態に戻せる。
nil は「退避していない」の意味に使っているので、t で記録する。"
  (warashi-nskk-cursor-test--with-frame
    (set-frame-parameter frame 'cursor-color nil)
    (warashi-nskk-cursor--apply-gui "red")
    (should (eq t (frame-parameter frame 'warashi-nskk-cursor-original)))
    (warashi-nskk-cursor--apply-gui nil)
    (should-not (frame-parameter frame 'cursor-color))
    (should-not (frame-parameter frame 'warashi-nskk-cursor-original))))

(ert-deftest warashi-nskk-cursor-test-gui-is-noop-without-original ()
  "色を付けていない状態で戻しても、フレームには触らない。"
  (warashi-nskk-cursor-test--with-frame
    (set-frame-parameter frame 'cursor-color "white")
    (warashi-nskk-cursor--apply-gui nil)
    (should (equal "white" (frame-parameter frame 'cursor-color)))))

;;;; TTY

(ert-deftest warashi-nskk-cursor-test-tty-spec ()
  "色名を端末が解釈できる rgb: 表記へ変換する。"
  (should (equal "rgb:ffff/0000/0000" (warashi-nskk-cursor--tty-spec "red")))
  (should-not (warashi-nskk-cursor--tty-spec nil))
  ;; 端末が知らない色名では何も送らない。文字列をそのまま流すと端末が壊れる。
  (should-not (warashi-nskk-cursor--tty-spec "no-such-color")))

(ert-deftest warashi-nskk-cursor-test-tty-sends-osc ()
  "色の設定は OSC 12、復帰は OSC 112 で通知する。"
  (warashi-nskk-cursor-test--with-terminal
    (warashi-nskk-cursor--apply-tty "red")
    (should (equal '("\e]12;rgb:ffff/0000/0000\a") warashi-nskk-cursor-test--sent))
    (warashi-nskk-cursor--apply-tty nil)
    (should (equal "\e]112\a" (car warashi-nskk-cursor-test--sent)))))

(ert-deftest warashi-nskk-cursor-test-tty-skips-unchanged ()
  "同じ色のあいだは端末へ送らない。post-command-hook から毎回走るため。"
  (warashi-nskk-cursor-test--with-terminal
    (warashi-nskk-cursor--apply-tty "red")
    (warashi-nskk-cursor--apply-tty "red")
    (should (= 1 (length warashi-nskk-cursor-test--sent)))))

(ert-deftest warashi-nskk-cursor-test-tty-reset-terminal ()
  "色を触った端末だけ復帰を送る。"
  (warashi-nskk-cursor-test--with-terminal
    (warashi-nskk-cursor-tty-reset-terminal (frame-terminal))
    (should-not warashi-nskk-cursor-test--sent)
    (warashi-nskk-cursor--apply-tty "red")
    (setq warashi-nskk-cursor-test--sent nil)
    (warashi-nskk-cursor-tty-reset-terminal (frame-terminal))
    (should (equal '("\e]112\a") warashi-nskk-cursor-test--sent))))

(ert-deftest warashi-nskk-cursor-test-tty-reset-all ()
  "終了時は触った端末を戻し、記録も落とす。"
  (warashi-nskk-cursor-test--with-terminal
    (warashi-nskk-cursor--apply-tty "red")
    (setq warashi-nskk-cursor-test--sent nil)
    (warashi-nskk-cursor-tty-reset-all)
    (should (equal '("\e]112\a") warashi-nskk-cursor-test--sent))
    (should-not (terminal-parameter nil 'warashi-nskk-cursor-tty-spec))
    ;; 二度目は送らない。
    (setq warashi-nskk-cursor-test--sent nil)
    (warashi-nskk-cursor-tty-reset-all)
    (should-not warashi-nskk-cursor-test--sent)))

;;;; 同期

(ert-deftest warashi-nskk-cursor-test-apply-reads-selected-window ()
  "カレントバッファではなく選択ウィンドウのバッファを見る。
window の変化 hook から呼ばれるときは両者が一致しているとは限らない。"
  (let ((shown (generate-new-buffer "warashi-nskk-cursor-test-shown"))
        (seen nil))
    (unwind-protect
        (progn
          (set-window-buffer (selected-window) shown)
          (cl-letf (((symbol-function 'warashi-nskk-cursor-color)
                     (lambda () (setq seen (current-buffer)) nil)))
            (with-temp-buffer
              (warashi-nskk-cursor-apply)))
          (should (eq shown seen)))
      (kill-buffer shown))))

(ert-deftest warashi-nskk-cursor-test-apply-safe-swallows-errors ()
  "hook から呼ぶ側では例外を外に出さない。
post-command-hook でエラーを出すと Emacs が hook から関数を外してしまい、
以後どのバッファでも同期が止まる。"
  (cl-letf (((symbol-function 'warashi-nskk-cursor-apply)
             (lambda () (error "boom"))))
    (should-not (warashi-nskk-cursor-apply-safe))))

(provide 'warashi-nskk-cursor-test)
;;; warashi-nskk-cursor-test.el ends here

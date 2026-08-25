;;; warashi-agent-shell-test.el --- 起動と表示まわりのテスト  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l warashi-agent-shell-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'agent-shell)
(require 'warashi-agent-shell)

(defvar warashi-agent-shell-test--state nil
  "テスト用の `agent-shell--state' の戻り値。")

(defmacro warashi-agent-shell-test--with-state (state &rest body)
  "`agent-shell--state' が STATE を返す状況で BODY を実行する。"
  (declare (indent 1))
  `(let ((warashi-agent-shell-test--state ,state))
     (cl-letf (((symbol-function 'agent-shell--state)
                (lambda (&rest _) warashi-agent-shell-test--state)))
       ,@body)))

;;;; 単キーコマンドに入力メソッドを奪わせない

(ert-deftest warashi-agent-shell-test-self-insert-uses-remap ()
  "プロンプト上では remap 先 (入力メソッド) に打鍵を渡す。"
  (let ((called nil))
    (cl-letf (((symbol-function 'agent-shell--typing-at-prompt-p) (lambda () t))
              ((symbol-function 'command-remapping) (lambda (&rest _) 'remapped))
              ((symbol-function 'call-interactively)
               (lambda (cmd &rest _) (setq called cmd))))
      (warashi-agent-shell--self-insert-via-remap
       (lambda () (setq called 'original)))
      (should (eq 'remapped called)))))

(ert-deftest warashi-agent-shell-test-self-insert-passes-through ()
  "プロンプト外と remap 無しでは元のコマンドをそのまま走らせる。
入力メソッドを使っていない状態での挙動を変えないため。"
  (dolist (case '((nil t) (t nil)))
    (cl-letf* ((typing (car case))
               (remap (cadr case))
               ((symbol-function 'agent-shell--typing-at-prompt-p)
                (lambda () typing))
               ((symbol-function 'command-remapping) (lambda (&rest _) remap)))
      (let ((args nil))
        (warashi-agent-shell--self-insert-via-remap
         (lambda (&rest a) (setq args a)) 'x 'y)
        (should (equal '(x y) args))))))

(ert-deftest warashi-agent-shell-test-self-insert-advice-covers-commands ()
  "self-insert を直接呼ぶコマンドは全て remap 経由に差し替わる。"
  (let ((installed nil))
    (cl-letf (((symbol-function 'advice-add)
               (lambda (fn how advice) (push (list fn how advice) installed))))
      (warashi-agent-shell-install-self-insert-advice))
    (dolist (fn warashi-agent-shell-self-insert-commands)
      (should (member (list fn :around #'warashi-agent-shell--self-insert-via-remap)
                      installed)))
    ;; 一覧に挙げたコマンドが agent-shell 側から消えていたら気付けるようにする。
    (dolist (fn warashi-agent-shell-self-insert-commands)
      (should (fboundp fn)))))

;;;; thought level

(ert-deftest warashi-agent-shell-test-thought-level-subscribes ()
  "config に thought level があれば init-finished で送る。"
  (let ((subscription nil)
        (sent nil))
    (cl-letf (((symbol-function 'agent-shell-subscribe-to)
               (lambda (&rest args) (setq subscription args)))
              ((symbol-function 'agent-shell--config-option-set-thought-level-id)
               (lambda (&rest args) (setq sent (plist-get args :thought-level-id)))))
      (warashi-agent-shell-test--with-state
          '((:agent-config . ((:warashi-thought-level . "xhigh"))))
        (warashi-agent-shell--apply-thought-level))
      (should (eq 'init-finished (plist-get subscription :event)))
      (should (eq (current-buffer) (plist-get subscription :shell-buffer)))
      ;; session 確立前には送らない。確立後のイベントで初めて送る。
      (should-not sent)
      (funcall (plist-get subscription :on-event) nil)
      (should (equal "xhigh" sent)))))

(ert-deftest warashi-agent-shell-test-thought-level-absent ()
  "thought level を持たない config では何もしない。"
  (let ((subscribed nil))
    (cl-letf (((symbol-function 'agent-shell-subscribe-to)
               (lambda (&rest _) (setq subscribed t))))
      (warashi-agent-shell-test--with-state '((:agent-config . nil))
        (warashi-agent-shell--apply-thought-level))
      (warashi-agent-shell-test--with-state nil
        (warashi-agent-shell--apply-thought-level))
      (should-not subscribed))))

;;;; 起動コマンド

(defmacro warashi-agent-shell-test--capture-dwim (&rest body)
  "BODY 中の `agent-shell--dwim' の引数を返す。"
  (declare (indent 0))
  `(let ((captured nil))
     (cl-letf (((symbol-function 'agent-shell-anthropic-make-claude-code-config)
                (lambda (&rest _) (list (cons :default-model-id #'ignore))))
               ((symbol-function 'agent-shell--dwim)
                (lambda (&rest args) (setq captured args))))
       ,@body)
     captured))

(ert-deftest warashi-agent-shell-test-start-claude-config ()
  "model と thought level が config に載り、新しい shell として起動する。"
  (let* ((captured (warashi-agent-shell-test--capture-dwim
                     (warashi-agent-shell--start-claude "opus[1m]" "low")))
         (config (plist-get captured :config)))
    (should (plist-get captured :new-shell))
    ;; :default-model-id は session 確立後に funcall される。
    (should (equal "opus[1m]" (funcall (alist-get :default-model-id config))))
    (should (equal "low" (alist-get :warashi-thought-level config)))))

(ert-deftest warashi-agent-shell-test-start-claude-keeps-model-per-shell ()
  "先に起動した shell の model が、後の起動で書き換わらない。
:default-model-id を動的束縛ではなく lexical に閉じ込めているため。"
  (let* ((first (alist-get :default-model-id
                           (plist-get (warashi-agent-shell-test--capture-dwim
                                        (warashi-agent-shell--start-claude "sonnet" "xhigh"))
                                      :config))))
    (warashi-agent-shell-test--capture-dwim
      (warashi-agent-shell--start-claude "opus[1m]" "low"))
    (should (equal "sonnet" (funcall first)))))

(ert-deftest warashi-agent-shell-test-define-claude-variants ()
  "variant ごとにコマンドと eshell 用の関数を定義する。"
  (warashi-agent-shell-define-claude-variants
   (warashi-agent-shell-test-variant "test-model" "high"))
  (should (commandp 'warashi-agent-shell-claude-warashi-agent-shell-test-variant))
  (should (fboundp 'eshell/claude-warashi-agent-shell-test-variant))
  (let ((args nil))
    (cl-letf (((symbol-function 'warashi-agent-shell--start-claude)
               (lambda (&rest a) (setq args a))))
      (funcall 'eshell/claude-warashi-agent-shell-test-variant)
      (should (equal '("test-model" "high") args)))))

;;;; コスト表示

(ert-deftest warashi-agent-shell-test-cost-indicator ()
  "累積コストを通貨記号付きで畳んで返す。"
  (warashi-agent-shell-test--with-state
      '((:usage . ((:cost-amount . 1.234) (:cost-currency . "USD"))))
    (should (equal "$1.23" (warashi-agent-shell--cost-indicator))))
  (warashi-agent-shell-test--with-state
      '((:usage . ((:cost-amount . 2.5))))
    (should (equal "$2.50" (warashi-agent-shell--cost-indicator))))
  ;; USD 以外は畳まずにそのまま出す。
  (warashi-agent-shell-test--with-state
      '((:usage . ((:cost-amount . 3) (:cost-currency . "EUR"))))
    (should (equal "EUR3.00" (warashi-agent-shell--cost-indicator)))))

(ert-deftest warashi-agent-shell-test-cost-indicator-empty ()
  "コストが無い、または 0 のあいだは何も出さない。"
  (warashi-agent-shell-test--with-state nil
    (should-not (warashi-agent-shell--cost-indicator)))
  (warashi-agent-shell-test--with-state '((:usage . nil))
    (should-not (warashi-agent-shell--cost-indicator)))
  (warashi-agent-shell-test--with-state '((:usage . ((:cost-amount . 0))))
    (should-not (warashi-agent-shell--cost-indicator))))

(ert-deftest warashi-agent-shell-test-append-cost-indicator ()
  "context indicator の後ろに cost を足す。"
  (warashi-agent-shell-test--with-state
      '((:usage . ((:cost-amount . 1.5))))
    (should (equal "80% $1.50" (warashi-agent-shell--append-cost-indicator "80%")))
    ;; context 未取得の段階で cost だけ返すと、header に何の値か分からない数字が
    ;; 現れる。
    (should-not (warashi-agent-shell--append-cost-indicator nil)))
  (warashi-agent-shell-test--with-state nil
    (should (equal "80%" (warashi-agent-shell--append-cost-indicator "80%")))))

(provide 'warashi-agent-shell-test)
;;; warashi-agent-shell-test.el ends here

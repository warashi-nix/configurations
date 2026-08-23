;;; nskk-corfu-henkan-test.el --- 変換候補 capf のテスト  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'nskk)
(require 'nskk-prolog)
(require 'nskk-corfu-henkan)

;; 学習データを ~/.emacs.d に書き出させない。モック辞書の候補が実環境に漏れる。
;; 保存は kill-emacs-hook でも走るので、let 束縛では間に合わない。
(setq nskk-search-learning-file
      (expand-file-name "nskk-corfu-test-learning.dat" temporary-file-directory))
(setq nskk-study-file
      (expand-file-name "nskk-corfu-test-study.dat" temporary-file-directory))

(defconst nskk-corfu-henkan-test--dict
  '(("かんじ"   . ("漢字" "感じ" "幹事"))
    ("かん"     . ("感" "缶"))
    ("かk"      . ("書" "掛" "欠"))
    ("ぬk"      . ("脱"))
    ("にほん"   . ("日本" "二本"))
    ("にっぽん" . ("日本"))
    ("たつ"     . ("裁つ"))
    ("たt"      . ("立" "建" "断"))
    ("おくt"    . ("送" "贈")))
  "テスト用のモック辞書。
かk と ぬk は送りあり見出し、にっぽん は にほん と表記が重なる見出し。
たつ と たt は送りなしと送りありが同じ読みに載る組、おくt は送り仮名が
促音から始まる組。")

(defmacro nskk-corfu-henkan-test--with-buffer (&rest body)
  "モック辞書と nskk-mode を用意したバッファで BODY を実行する。"
  (declare (indent 0))
  `(progn
     (nskk-prolog-assert '((dict-initialized)))
     (nskk-prolog-retract-all 'user-dict-entry 2)
     (nskk-prolog-set-index 'user-dict-entry 2 :trie)
     ;; 学習は Prolog の facts なのでテストをまたいで残る。候補順を見るテスト
     ;; が互いの学習結果を拾わないように毎回落とす。
     (nskk-prolog-retract-all 'learning-score 3)
     (nskk-prolog-retract-all 'study-association 3)
     (nskk-prolog-retract-all 'dict-annotation 3)
     (setq nskk--study-kakutei-ring nil)
     (setq nskk-corfu-henkan--candidates nil)
     (dolist (entry nskk-corfu-henkan-test--dict)
       (nskk-prolog-assert `((user-dict-entry ,(car entry) ,(cdr entry)))))
     (with-temp-buffer
       (setq unread-command-events nil)
       (electric-indent-local-mode -1)
       (nskk-mode 1)
       (nskk--set-mode 'hiragana)
       (setq nskk--romaji-buffer "")
       (nskk-corfu-henkan-setup)
       (unwind-protect (progn ,@body)
         (ignore-errors (nskk-mode -1))
         (setq unread-command-events nil)))))

(defun nskk-corfu-henkan-test--type (keys)
  "KEYS をキー入力として流し込む。
execute-kbd-macro は batch でイベントキューを汚すので、nskk の E2E
ヘルパと同じく 1 キーずつ call-interactively で打ち込む。"
  (let ((vec (kbd keys)))
    (cl-loop for i from 0 below (length vec)
             do (let* ((event (aref vec i))
                       (cmd (key-binding (vector event)))
                       (last-command-event event))
                  (setq this-command cmd)
                  (when cmd (call-interactively cmd))))))

(defun nskk-corfu-henkan-test--elements (completions)
  "completion-all-completions の戻り値から候補だけを取り出す。
末尾には base サイズが cdr として付いているので普通のリストではない。"
  (let (acc)
    (while (consp completions)
      (push (car completions) acc)
      (setq completions (cdr completions)))
    (nreverse acc)))

(ert-deftest nskk-corfu-henkan-test-preedit-returns-conversion-candidates ()
  "▽ の読みに対して、読みの前方一致ではなく変換候補が返る。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a n j i")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (should capf)
      (should (equal (buffer-substring-no-properties (nth 0 capf) (nth 1 capf))
                     "かんじ"))
      (should (equal (all-completions "かんじ" (nth 2 capf))
                     '("漢字" "感じ" "幹事"))))))

(ert-deftest nskk-corfu-henkan-test-candidates-survive-completion-styles ()
  "補完スタイルを通しても候補が落ちない。読みと候補は文字が重ならない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a n j i")
    (let* ((capf (nskk-corfu-henkan-at-point))
           (completion-styles '(basic partial-completion flex))
           (result (completion-all-completions
                    "かんじ" (nth 2 capf) nil (length "かんじ"))))
      (should (equal (nskk-corfu-henkan-test--elements result)
                     '("漢字" "感じ" "幹事"))))))

(ert-deftest nskk-corfu-henkan-test-no-preedit-returns-nil ()
  "▽ でないときは capf を名乗らない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "k a n j i")
    (should-not (nskk-corfu-henkan-at-point))))

(ert-deftest nskk-corfu-henkan-test-unknown-reading-yields-no-candidates ()
  "辞書に無い読みでは候補が空になる。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "N u")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (should capf)
      (should (equal (all-completions "ぬ" (nth 2 capf)) nil)))))

(ert-deftest nskk-corfu-henkan-test-preedit-is-exclusive ()
  "▽ のあいだは候補が空でも capf を占有し、他の capf に落ちない。
落ちると nskk-completion-at-point の読み補完が出て、RET で読みが確定する。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "N u")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (should-not (eq (plist-get (nthcdr 3 capf) :exclusive) 'no)))
    ;; 読み補完より先に呼ばれること。exclusive はそれで初めて意味を持つ。
    (should (< (cl-position 'nskk-corfu-henkan-at-point
                            completion-at-point-functions)
               (cl-position 'nskk-completion-at-point
                            completion-at-point-functions)))))

(ert-deftest nskk-corfu-henkan-test-fallback-blocked-when-empty ()
  "候補が空でも読み補完に落ちない。
▽ぬ は変換候補が空だが、読み補完には見出し ぬk が引ける。事故が再発する
ならこの状態で、popup に ぬk が出て RET で読みが確定する。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "N u")
    ;; 読み補完の方には候補がある、という前提を先に固定する。
    (should (nskk--dcomp-search-prefix "ぬ"))
    (should (equal (all-completions "ぬ" (nth 2 (nskk-corfu-henkan-at-point))) nil))
    (let ((inhibit-message t))
      (completion-at-point))
    (should (equal (buffer-string) "▽ぬ"))))

(ert-deftest nskk-corfu-henkan-test-prefix-match-supplies-candidates ()
  "ローマ字が残った ▽にほ でも、見出しの前方一致から変換候補が出る。
これが読み補完を置き換える本体で、RET が読みを確定させる事故を消す。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "N i h o n")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (should (equal (buffer-substring-no-properties (nth 0 capf) (nth 1 capf))
                     "にほ"))
      (should (equal (all-completions "にほ" (nth 2 capf))
                     '("日本" "二本"))))))

(ert-deftest nskk-corfu-henkan-test-exact-comes-before-prefix ()
  "完全一致の候補が前方一致より先に並ぶ。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a n")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (should (equal (all-completions "かん" (nth 2 capf))
                     '("感" "缶" "漢字" "感じ" "幹事"))))))

(ert-deftest nskk-corfu-henkan-test-okuri-headwords-excluded ()
  "送りあり見出しは前方一致に混ぜない。送り仮名なしでは確定できない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a")
    (let* ((nskk-corfu-henkan-prefix-min-length 1)
           (candidates (all-completions "か" (nth 2 (nskk-corfu-henkan-at-point)))))
      (should (member "感" candidates))
      (should-not (member "書" candidates)))))

(ert-deftest nskk-corfu-henkan-test-duplicate-word-keeps-first-headword ()
  "同じ表記が複数の見出しから出たら先勝ちで一つにする。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "N i")
    (let* ((nskk-corfu-henkan-prefix-min-length 1)
           (candidates (all-completions "に" (nth 2 (nskk-corfu-henkan-at-point)))))
      ;; にほん が にっぽん より先。日本 は一つだけ。
      (should (equal candidates '("日本" "二本"))))))

(ert-deftest nskk-corfu-henkan-test-prefix-limit-caps-headwords ()
  "前方一致で引く見出しの数に上限がある。実辞書では ▽か が数千件になる。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a")
    (let* ((nskk-corfu-henkan-prefix-min-length 1)
           (nskk-corfu-henkan-prefix-limit 1)
           (candidates (all-completions "か" (nth 2 (nskk-corfu-henkan-at-point)))))
      (should (equal candidates '("感" "缶"))))))

(ert-deftest nskk-corfu-henkan-test-short-reading-skips-prefix-match ()
  "読みが 1 文字のうちは前方一致を引かない。実辞書では 1 万件近く該当する。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a")
    (let ((candidates (all-completions "か" (nth 2 (nskk-corfu-henkan-at-point)))))
      ;; かん / かんじ は前方一致でしか引けないので候補が残らない
      (should-not candidates))
    ;; 下限を外せば同じ読みで前方一致が引ける
    (let* ((nskk-corfu-henkan-prefix-min-length 1)
           (candidates (all-completions "か" (nth 2 (nskk-corfu-henkan-at-point)))))
      (should (member "感" candidates)))))

(ert-deftest nskk-corfu-henkan-test-learn-uses-matched-headword ()
  "学習には打った読みではなく、一致した見出しを渡す。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "N i h o n")
    (let ((capf (nskk-corfu-henkan-at-point))
          (learned nil))
      (all-completions "にほ" (nth 2 capf))
      (delete-region (nth 0 capf) (nth 1 capf))
      (insert "日本")
      (cl-letf (((symbol-function 'nskk-search-learn)
                 (lambda (reading word) (setq learned (cons reading word)))))
        (funcall (plist-get (nthcdr 3 capf) :exit-function) "日本" 'finished))
      (should (equal learned '("にほん" . "日本"))))))

(ert-deftest nskk-corfu-henkan-test-okurigana-marker-yields-no-candidates ()
  "送り開始直後の ▽か* では候補を出さない。送りありは別タスク。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a K")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (should capf)
      (should (equal (all-completions "か*" (nth 2 capf)) nil)))))

(ert-deftest nskk-corfu-henkan-test-exit-removes-marker-and-state ()
  "候補を選ぶと ▽ が消え、preedit 状態が残らない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a n j i")
    (let ((capf (nskk-corfu-henkan-at-point)))
      ;; corfu がやる region の置換を手で再現してから exit-function を呼ぶ。
      (delete-region (nth 0 capf) (nth 1 capf))
      (insert "漢字")
      (funcall (plist-get (nthcdr 3 capf) :exit-function) "漢字" 'finished))
    (should (equal (buffer-string) "漢字"))
    (should-not (nskk--get-conversion-start))
    (should (equal nskk--romaji-buffer ""))))

(ert-deftest nskk-corfu-henkan-test-table-follows-reading ()
  "読みが縮んだら候補も追従する。corfu は同じ table を使い回す。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a n j i")
    (let ((table (nth 2 (nskk-corfu-henkan-at-point))))
      (should (equal (all-completions "かんじ" table) '("漢字" "感じ" "幹事")))
      ;; DEL で ▽かん になっても、corfu は capf を引き直さず table を使い回す。
      (nskk-corfu-henkan-test--type "DEL")
      (should (equal (all-completions "かん" table)
                     '("感" "缶" "漢字" "感じ" "幹事"))))))

(ert-deftest nskk-corfu-henkan-test-okuri-splits-are-longest-stem-first ()
  "読みは (語幹 . 送り) の全分割になる。語幹の長い順。"
  (should (equal (nskk-corfu-henkan--okuri-splits "かく") '(("か" . "く"))))
  (should (equal (nskk-corfu-henkan--okuri-splits "ばりかた")
                 '(("ばりか" . "た") ("ばり" . "かた") ("ば" . "りかた"))))
  ;; 1 文字の読みは分割できない。語幹の無い語は無い。
  (should (equal (nskk-corfu-henkan--okuri-splits "か") nil))
  (should (equal (nskk-corfu-henkan--okuri-splits "") nil)))

(ert-deftest nskk-corfu-henkan-test-okuri-midasi-uses-first-consonant ()
  "見出しは語幹 + 送り仮名の先頭のローマ字子音。"
  (should (equal (nskk-corfu-henkan--okuri-midasi "か" "く") "かk"))
  (should (equal (nskk-corfu-henkan--okuri-midasi "おく" "った") "おくt"))
  ;; 送りが っ だけのときはタ行が来るものとして t を当てる (libskk と同じ)。
  (should (equal (nskk-corfu-henkan--okuri-midasi "おく" "っ") "おくt"))
  ;; 続きがあるなら促音を飛ばしてその子音。タ行と決め打ちはしない。
  (should (equal (nskk-corfu-henkan--okuri-midasi "ぶ" "っか") "ぶk"))
  ;; ローマ字に落ちないかなは見出しを組めない。
  (should-not (nskk-corfu-henkan--okuri-midasi "か" "、")))

(ert-deftest nskk-corfu-henkan-test-okuri-candidates-appear-in-preedit ()
  "▽たつ に送り仮名付きの候補が出る。送りなしが先、送りありが後。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "T a t u")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (should (equal (buffer-substring-no-properties (nth 0 capf) (nth 1 capf))
                     "たつ"))
      (should (equal (all-completions "たつ" (nth 2 capf))
                     '("裁つ" "立つ" "建つ" "断つ"))))))

(ert-deftest nskk-corfu-henkan-test-okuri-candidates-handle-sokuon ()
  "促音から始まる送り仮名でも見出しが引ける。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "O k u t t a")
    (should (equal (all-completions "おくった" (nth 2 (nskk-corfu-henkan-at-point)))
                   '("送った" "贈った")))))

(ert-deftest nskk-corfu-henkan-test-okuri-learn-uses-midasi-and-stem ()
  "送りあり候補の学習は見出し たt と語 立 を渡す。送り仮名は付けない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "T a t u")
    (let ((capf (nskk-corfu-henkan-at-point))
          (learned nil))
      (all-completions "たつ" (nth 2 capf))
      (delete-region (nth 0 capf) (nth 1 capf))
      (insert "立つ")
      (cl-letf (((symbol-function 'nskk-search-learn)
                 (lambda (reading word) (setq learned (cons reading word)))))
        (funcall (plist-get (nthcdr 3 capf) :exit-function) "立つ" 'finished))
      (should (equal learned '("たt" . "立"))))))

(ert-deftest nskk-corfu-henkan-test-learning-orders-exact-candidates ()
  "同じ読みで前に選んだ候補が、次からその読みの先頭に来る。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "N i h o n n")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (should (equal (all-completions "にほん" (nth 2 capf)) '("日本" "二本")))
      (delete-region (nth 0 capf) (nth 1 capf))
      (insert "二本")
      (funcall (plist-get (nthcdr 3 capf) :exit-function) "二本" 'finished))
    (nskk-corfu-henkan-test--type "N i h o n n")
    (should (equal (all-completions "にほん" (nth 2 (nskk-corfu-henkan-at-point)))
                   '("二本" "日本")))))

(ert-deftest nskk-corfu-henkan-test-learning-orders-okuri-candidates ()
  "送りあり候補にも学習が効く。送りなしの枠は動かない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "T a t u")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (should (equal (all-completions "たつ" (nth 2 capf))
                     '("裁つ" "立つ" "建つ" "断つ")))
      (delete-region (nth 0 capf) (nth 1 capf))
      (insert "建つ")
      (funcall (plist-get (nthcdr 3 capf) :exit-function) "建つ" 'finished))
    (nskk-corfu-henkan-test--type "T a t u")
    (should (equal (all-completions "たつ" (nth 2 (nskk-corfu-henkan-at-point)))
                   '("裁つ" "建つ" "立つ" "断つ")))))

(ert-deftest nskk-corfu-henkan-test-learning-keeps-headword-order ()
  "学習が並べ替えるのは見出しの中だけ。完全一致が前方一致より先なのは変わらない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a n j i")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (all-completions "かんじ" (nth 2 capf))
      (delete-region (nth 0 capf) (nth 1 capf))
      (insert "幹事")
      (funcall (plist-get (nthcdr 3 capf) :exit-function) "幹事" 'finished))
    (nskk-corfu-henkan-test--type "K a n")
    (should (equal (all-completions "かん" (nth 2 (nskk-corfu-henkan-at-point)))
                   '("感" "缶" "幹事" "漢字" "感じ")))))

(ert-deftest nskk-corfu-henkan-test-exit-records-kakutei-history ()
  "確定した語を nskk-study の履歴に積む。積まないと文脈連想が永久に効かない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a n j i")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (all-completions "かんじ" (nth 2 capf))
      (delete-region (nth 0 capf) (nth 1 capf))
      (insert "漢字")
      (funcall (plist-get (nthcdr 3 capf) :exit-function) "漢字" 'finished))
    (should (equal (plist-get (car nskk--study-kakutei-ring) :word) "漢字"))))

(ert-deftest nskk-corfu-henkan-test-study-association-promotes-candidate ()
  "直前に確定した語との連想に当たった候補が先頭に来る。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-corfu-henkan-test--type "K a n j i")
    (let ((capf (nskk-corfu-henkan-at-point)))
      (all-completions "かんじ" (nth 2 capf))
      (delete-region (nth 0 capf) (nth 1 capf))
      (insert "漢字")
      (funcall (plist-get (nthcdr 3 capf) :exit-function) "漢字" 'finished))
    ;; 学習スコアではなく連想だけで効くことを見たいので facts を直接置く。
    (nskk-prolog-assert '((study-association "漢字" "にほん" "二本")))
    (nskk-corfu-henkan-test--type "N i h o n n")
    (should (equal (all-completions "にほん" (nth 2 (nskk-corfu-henkan-at-point)))
                   '("二本" "日本")))))

(ert-deftest nskk-corfu-henkan-test-annotation-shows-for-candidate ()
  "註釈付きの候補には註釈が付いて出る。註釈の無い候補には何も付かない。"
  (nskk-corfu-henkan-test--with-buffer
    ;; dict-annotation は辞書の読み込み時にしか積まれない。モック辞書は
    ;; facts を直接置いているので、註釈も直接登録する。
    (nskk-annotation-register "かんじ" "幹事" "party organizer")
    (let ((nskk-show-annotation t))
      (nskk-corfu-henkan-test--type "K a n j i")
      (let* ((capf (nskk-corfu-henkan-at-point))
             (annotate (plist-get (nthcdr 3 capf) :annotation-function)))
        (all-completions "かんじ" (nth 2 capf))
        (should (equal (substring-no-properties (funcall annotate "幹事"))
                       " [party organizer]"))
        (should-not (funcall annotate "漢字"))))))

(ert-deftest nskk-corfu-henkan-test-annotation-uses-midasi-and-word ()
  "送りあり候補の註釈は見出し たt と語 立 で引く。表示の 立つ では引けない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-annotation-register "たt" "立" "stand")
    (let ((nskk-show-annotation t))
      (nskk-corfu-henkan-test--type "T a t u")
      (let* ((capf (nskk-corfu-henkan-at-point))
             (annotate (plist-get (nthcdr 3 capf) :annotation-function)))
        (all-completions "たつ" (nth 2 capf))
        (should (equal (substring-no-properties (funcall annotate "立つ"))
                       " [stand]"))))))

(ert-deftest nskk-corfu-henkan-test-annotation-respects-show-flag ()
  "nskk-show-annotation が nil なら註釈を出さない。"
  (nskk-corfu-henkan-test--with-buffer
    (nskk-annotation-register "かんじ" "幹事" "party organizer")
    (let ((nskk-show-annotation nil))
      (nskk-corfu-henkan-test--type "K a n j i")
      (let* ((capf (nskk-corfu-henkan-at-point))
             (annotate (plist-get (nthcdr 3 capf) :annotation-function)))
        (all-completions "かんじ" (nth 2 capf))
        (should-not (funcall annotate "幹事"))))))

(provide 'nskk-corfu-henkan-test)
;;; nskk-corfu-henkan-test.el ends here

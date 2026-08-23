;;; nskk-corfu-henkan.el --- SKK の変換候補を capf として返す  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Shinnosuke Sawada-Dazai

;; Author: Shinnosuke Sawada-Dazai <shin@warashi.dev>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (nskk "0.3.0") (corfu "1.0"))
;; Keywords: i18n, japanese, convenience

;;; Commentary:

;; nskk の ▽ (preedit) 状態にいるあいだ、読みに対する変換候補を
;; completion-at-point-functions として返し、corfu に選ばせる。skkeleton
;; + ddc で使っている体験を Emacs 側に持ってくるためのもの。
;;
;; nskk-completion-at-point は流用できない。あれが返すのは辞書の見出し語
;; (読み) の前方一致であって、変換候補ではない。ここで流用するのは region
;; 計算 (nskk--get-conversion-start / nskk--skip-marker-pos) と、見出しの
;; 前方一致検索 (nskk--dcomp-search-prefix) だけ。

;;; Code:

(require 'nskk)
(require 'nskk-henkan)
;; 文脈連想は nskk 本体が optional 扱いで require しない (nskk.el:115 は
;; declare-function だけ)。候補順に効かせたいのでここで確実に読む。
(require 'nskk-study)
(require 'nskk-annotation)
(require 'nskk-prolog)

;; corfu は require しない。この capf 自体は corfu が無くても動き、テスト
;; も corfu 抜きで回すため。キーと発火条件の辻褄合わせだけ featurep で
;; 見て行う。
(declare-function corfu-next "corfu")
(declare-function corfu-previous "corfu")
(defvar corfu-map)
(defvar corfu-auto-commands)

(defvar nskk-corfu-henkan-prefix-limit 20
  "前方一致で辞書を引く見出しの数の上限。
見出し 1 つにつき辞書引きが 1 回走り、それが打鍵ごとに起きる。実辞書で
は ▽か だけで数千の見出しが該当するので上限が要る。")

(defvar nskk-corfu-henkan-prefix-min-length 2
  "前方一致を引き始める読みの長さ。
実辞書では 1 文字の読みが 1 万件近い見出しに前方一致し、trie の全走査で
打鍵ごとに 0.1 秒以上かかる。しかも候補がノイズだらけになる。1 文字の
うちは完全一致と送りありだけを引く。")

(defvar nskk-corfu-henkan--marker-start nil
  "直近に返した capf の ▽ マーカー位置。
exit-function は corfu が region を置換した後に呼ばれるので、その時点
では読みから位置を再計算できない。")

(defvar nskk-corfu-henkan--candidates nil
  "table が最後に組んだ (表示 . (見出し . 語)) の alist。
学習には打った読みではなく、その候補が実際に載っていた見出しと、辞書に
載っている語そのものを渡す。▽にほ から 日本 を選んだときの見出しは
にほん、▽たつ から 立つ を選んだときの見出しは たt で語は 立。")

(defun nskk-corfu-henkan--candidate-word (candidate)
  "CANDIDATE から表示文字列を取り出す。注釈付きの構造体にも耐える。"
  (cond
   ((stringp candidate) candidate)
   ((consp candidate) (format "%s" (car candidate)))
   (t (format "%s" candidate))))

(defun nskk-corfu-henkan--score (midasi word)
  "MIDASI に対する WORD の学習スコア。学習していなければ 0。"
  (or (nskk-prolog-query-value
       `(learning-score ,midasi ,word \?s) '\?s)
      0))

(defun nskk-corfu-henkan--rank (midasi words)
  "見出し MIDASI の候補 WORDS を学習の効いた順に並べ替える。

学習スコアの降順に並べ、同点は辞書の並びのまま残す (sort は安定)。その後
に nskk-study-reorder を通し、直前に確定した語との連想に当たった候補を先
頭へ上げる。

スコアの並べ替えは nskk 本体の ▼ には無い。nskk-search-learn が積む
learning-score/3 を読んでいるのは前方一致の見出しの並べ替え
(nskk--search-reading-score) だけで、exact 引きの候補列には効かない。同じ
読みを打ち直したときに前回選んだ候補が先頭に来る skkeleton/ddskk の挙動が
欲しいので capf 側で足している。"
  (let ((ranked (sort (copy-sequence words)
                      (lambda (a b)
                        (> (nskk-corfu-henkan--score midasi a)
                           (nskk-corfu-henkan--score midasi b))))))
    (nskk-study-reorder midasi ranked)))

(defun nskk-corfu-henkan--lookup (reading)
  "READING の変換候補リストを返す。見つからなければ nil。
nskk-core-search/k は CPS だが、辞書引きの継続はこの場で同期に呼ばれる。"
  (let ((found nil))
    (nskk-core-search/k reading :exact nil
                        (lambda (candidates) (setq found candidates))
                        #'ignore)
    (nskk-corfu-henkan--rank
     reading
     (mapcar #'nskk-corfu-henkan--candidate-word found))))

(defun nskk-corfu-henkan--okuri-key-p (key)
  "KEY が送りあり見出しなら non-nil。
送りあり見出しは かk のように送り開始のローマ字で終わる。読みだけでは
送り仮名が決まらないので、前方一致の対象から外す。"
  (and (> (length key) 0)
       (let ((last (aref key (1- (length key)))))
         (and (>= last ?a) (<= last ?z)))))

(defun nskk-corfu-henkan--prefix-keys (reading)
  "READING を前方一致の接頭辞として引いた見出しを返す。
短い見出しほど打った読みに近いので、長さ順に並べてから上限で切る。
読みが nskk-corfu-henkan-prefix-min-length に満たないうちは引かない。"
  (when (>= (length reading) nskk-corfu-henkan-prefix-min-length)
    (let ((keys (seq-remove #'nskk-corfu-henkan--okuri-key-p
                            (nskk--dcomp-search-prefix reading))))
      (setq keys (sort keys (lambda (a b)
                              (if (= (length a) (length b))
                                  (string< a b)
                                (< (length a) (length b))))))
      (seq-take keys nskk-corfu-henkan-prefix-limit))))

(defconst nskk-corfu-henkan--okuri-consonants
  '(
    ("ぁ" . "x")
    ("あ" . "a")
    ("ぃ" . "x")
    ("い" . "i")
    ("ぅ" . "x")
    ("う" . "u")
    ("ぇ" . "x")
    ("え" . "e")
    ("ぉ" . "x")
    ("お" . "o")
    ("か" . "k")
    ("が" . "g")
    ("き" . "k")
    ("ぎ" . "g")
    ("く" . "k")
    ("ぐ" . "g")
    ("け" . "k")
    ("げ" . "g")
    ("こ" . "k")
    ("ご" . "g")
    ("さ" . "s")
    ("ざ" . "z")
    ("し" . "s")
    ("じ" . "j")
    ("す" . "s")
    ("ず" . "z")
    ("せ" . "s")
    ("ぜ" . "z")
    ("そ" . "s")
    ("ぞ" . "z")
    ("た" . "t")
    ("だ" . "d")
    ("ち" . "t")
    ("ぢ" . "d")
    ("っ" . "x")
    ("つ" . "t")
    ("づ" . "d")
    ("て" . "t")
    ("で" . "d")
    ("と" . "t")
    ("ど" . "d")
    ("な" . "n")
    ("に" . "n")
    ("ぬ" . "n")
    ("ね" . "n")
    ("の" . "n")
    ("は" . "h")
    ("ば" . "b")
    ("ぱ" . "p")
    ("ひ" . "h")
    ("び" . "b")
    ("ぴ" . "p")
    ("ふ" . "h")
    ("ぶ" . "b")
    ("ぷ" . "p")
    ("へ" . "h")
    ("べ" . "b")
    ("ぺ" . "p")
    ("ほ" . "h")
    ("ぼ" . "b")
    ("ぽ" . "p")
    ("ま" . "m")
    ("み" . "m")
    ("む" . "m")
    ("め" . "m")
    ("も" . "m")
    ("ゃ" . "x")
    ("や" . "y")
    ("ゅ" . "x")
    ("ゆ" . "y")
    ("ょ" . "x")
    ("よ" . "y")
    ("ら" . "r")
    ("り" . "r")
    ("る" . "r")
    ("れ" . "r")
    ("ろ" . "r")
    ("ゎ" . "x")
    ("わ" . "w")
    ("ゐ" . "x")
    ("ゑ" . "x")
    ("を" . "w")
    ("ん" . "n")
)
  "送り仮名の先頭のかなから、辞書の見出しに使うローマ字子音を引く表。
nskk はかな→ローマ字の逆引きを持たないので、skkeleton の okuriTable
(denops/skkeleton/okuri.ts) を移してきた。")

(defconst nskk-corfu-henkan--sokuon "っ"
  "促音。送り仮名の先頭に来ると子音が決まらないので別扱いにする。")

(defun nskk-corfu-henkan--okuri-splits (reading)
  "READING を (語幹 . 送り仮名) の全分割にする。語幹の長い順。
どこから送り仮名かは打った時点では決まらないので、全部試して辞書に当たっ
たものだけを候補にする。1 文字の読みは語幹が空になるので分割しない。"
  (let ((chars (string-to-list reading))
        (acc nil))
    (dotimes (i (max 0 (1- (length reading))))
      (let ((split (1+ i)))
        (push (cons (concat (seq-take chars split))
                    (concat (seq-drop chars split)))
              acc)))
    acc))

(defun nskk-corfu-henkan--okuri-midasi (stem okuri)
  "STEM と OKURI から送りあり見出しを組む。子音が引けなければ nil。
送り仮名が っ だけのときはタ行が続くものとして t を当てる。促音の大半が
タ行だという調査に基づく libskk の挙動で、skkeleton もこれに合わせてい
る。続きがあるなら促音を飛ばしてその子音を使う (った なら t、っか なら k)。"
  (let* ((head (seq-find (lambda (c)
                           (not (equal (char-to-string c)
                                       nskk-corfu-henkan--sokuon)))
                         (string-to-list okuri)))
         (consonant (if head
                        (cdr (assoc (char-to-string head)
                                    nskk-corfu-henkan--okuri-consonants))
                      (and (equal okuri nskk-corfu-henkan--sokuon) "t"))))
    (and consonant (concat stem consonant))))

(defun nskk-corfu-henkan--collect-okuri (reading)
  "READING を送りありとして読んだときの (表示 . (見出し . 語)) を返す。
表示は候補に送り仮名を付け直したもの。▽かく の見出し かk から引いた 書
は 書く として出す。大文字の送り開始 (KaKu) を打たなくても送りありが引
けるのがこの経路の役目で、vim 側の skkeleton も同じ形で出している。"
  (let (acc)
    (dolist (split (nskk-corfu-henkan--okuri-splits reading))
      (let ((midasi (nskk-corfu-henkan--okuri-midasi (car split) (cdr split))))
        (when midasi
          (dolist (word (nskk-corfu-henkan--lookup midasi))
            (push (cons (concat word (cdr split)) (cons midasi word)) acc)))))
    (nreverse acc)))

(defun nskk-corfu-henkan--collect (reading)
  "READING に対する (候補 . 見出し) の alist を組む。
完全一致が先、その後に見出しの前方一致。表記が重なったら先勝ちで一つに
する。この前方一致が読み補完の役目を吸収していて、ローマ字が残った
▽にほ でも 日本 が出る。"
  (let ((seen (make-hash-table :test #'equal))
        (acc nil))
    (dolist (key (cons reading (nskk-corfu-henkan--prefix-keys reading)))
      (dolist (word (nskk-corfu-henkan--lookup key))
        (unless (gethash word seen)
          (puthash word t seen)
          (push (cons word (cons key word)) acc))))
    (dolist (entry (nskk-corfu-henkan--collect-okuri reading))
      (unless (gethash (car entry) seen)
        (puthash (car entry) t seen)
        (push entry acc)))
    (nreverse acc)))

(defun nskk-corfu-henkan--table (string _pred action)
  "読み STRING の変換候補を素通しする completion table。

候補は漢字で、入力文字列は読みなので、通常の table だと補完スタイルに
全部フィルタで落とされる。all-completions (action t) で無条件に全件返す
ことでそれを避ける。

候補は STRING から毎回引き直す。corfu は popup が出ているあいだ capf を
呼び直さず同じ table を使い回すので、候補を閉じ込めると DEL で読みが縮
んでも古い候補が残る。"
  (cond
   ((eq action 'metadata)
    '(metadata (category . nskk-henkan)
               (display-sort-function . identity)
               (cycle-sort-function . identity)))
   ((eq (car-safe action) 'boundaries) nil)
   ((eq action t)
    (setq nskk-corfu-henkan--candidates (nskk-corfu-henkan--collect string))
    (mapcar #'car nskk-corfu-henkan--candidates))
   ;; try-completion が共通接頭辞を返すと読みが漢字の断片に置き換わる。
   ;; 読みをそのまま返して「これ以上補完できない」ことにする。ついでに
   ;; フォールバックも塞いでいる。completion--capf-wrapper は :exclusive no
   ;; の capf を try-completion が nil のときだけ捨てる (minibuffer.el:3264)。
   ((null action) string)
   ((eq action 'lambda)
    (and (assoc string (nskk-corfu-henkan--collect string)) t))
   (t nil)))

(defun nskk-corfu-henkan--annotation (candidate)
  "CANDIDATE の註釈を corfu に出す形で返す。無ければ nil。

註釈は表示文字列ではなく (見出し . 語) で引く。送りあり候補の表示は 立つ
だが、辞書に載っているのは見出し たt の 立 なので、表示文字列では当たら
ない。

註釈の facts (dict-annotation/3) が積まれるのは nskk-show-annotation が
non-nil のときの辞書読み込み時だけ。フラグを見るのは echo area 表示
(nskk-annotation-show-for-candidate) と揃えるため。"
  (when nskk-show-annotation
    (when-let* ((entry (cdr (assoc candidate nskk-corfu-henkan--candidates)))
                (annotation (nskk-annotation-lookup (car entry) (cdr entry))))
      (nskk--annotation-format annotation))))

(defun nskk-corfu-henkan--exit (chosen status)
  "corfu が CHOSEN を挿入した後に ▽ を片付けて確定する。"
  (when (and (memq status '(finished exact)) nskk-corfu-henkan--marker-start)
    (let* ((start nskk-corfu-henkan--marker-start)
           (entry (cdr (assoc chosen nskk-corfu-henkan--candidates)))
           (reading (car-safe entry))
           (word (cdr-safe entry)))
      (save-excursion
        (goto-char start)
        (when (looking-at nskk-henkan-on-marker-regexp)
          (delete-region start (match-end 0))))
      (nskk--clear-conversion-start-marker)
      (nskk--reset-romaji-buffer)
      (nskk-with-current-state
        (nskk-state-set-henkan-phase nskk-current-state nil))
      (when (and reading word)
        ;; nskk 本体の確定と同じ順で同じものを呼ぶ (nskk-henkan.el:1509)。
        ;; after-kakutei を抜かすと確定履歴が空のままになり、
        ;; nskk-study-reorder が永久に no-op になる。
        (let ((index (seq-position (mapcar #'car nskk-corfu-henkan--candidates)
                                   chosen)))
          (ignore-errors (nskk-study-after-kakutei reading word index)))
        (ignore-errors (nskk-search-learn reading word)))))
  (setq nskk-corfu-henkan--marker-start nil
        nskk-corfu-henkan--candidates nil))

(defun nskk-corfu-henkan-at-point ()
  "▽ モードの読みに対する変換候補を capf として返す。

候補が空でも ▽ にいる限り capf を名乗り、exclusive のまま返す。ここで
nil を返すと nskk-completion-at-point の読み補完に落ち、popup で RET を
押したときに読みがそのまま確定してしまう。占有条件を
nskk-completion-at-point と同じにしてあるので、▽ 中は必ずこちらが勝つ。"
  (when-let* ((start (nskk--get-conversion-start))
              (text-start (nskk--skip-marker-pos
                           start nskk-henkan-on-marker-regexp))
              (_ (> (point) text-start)))
    (setq nskk-corfu-henkan--marker-start start)
    (list text-start
          (point)
          #'nskk-corfu-henkan--table
          :annotation-function #'nskk-corfu-henkan--annotation
          :exit-function #'nskk-corfu-henkan--exit)))

(defun nskk-corfu-henkan--integrate-corfu ()
  "corfu と nskk のキー・発火条件の食い違いを埋める。
corfu の C-n / C-p は [remap next-line] 経由なので、nskk-mode-map が C-n を
直接握っていると popup に届かない。corfu-map に直接足して通す。corfu-auto も
self-insert-command しか見ていないが、nskk は remap で nskk-self-insert に
差し替えているので、こちらも足しておく。"
  (when (featurep 'corfu)
    (keymap-set corfu-map "C-n" #'corfu-next)
    (keymap-set corfu-map "C-p" #'corfu-previous))
  (when (boundp 'corfu-auto-commands)
    (dolist (cmd '(nskk-self-insert nskk-handle-backspace))
      (add-to-list 'corfu-auto-commands cmd))))

(defun nskk-corfu-henkan-setup ()
  "現在のバッファで変換候補の capf を有効にする。
nskk-mode を有効にした後に呼ぶこと。"
  (add-hook 'completion-at-point-functions
            #'nskk-corfu-henkan-at-point -10 t)
  (nskk-corfu-henkan--integrate-corfu))

(provide 'nskk-corfu-henkan)
;;; nskk-corfu-henkan.el ends here

; # x-awk -- POSIX awk on x-lang
;
; ## awk/eval.x -- running a program over records
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; MEANING LIVES HERE (crafting-a-lang.md section 3): the parser emits shapes,
; this file says what they do.  awk-run is the pure core -- program text and
; input text in, print output to stdout, no other doors -- which is what
; keeps the specs one-line.
;
; THE VALUE MODEL, POSIX's three kinds plus absence:
;   number   an x NUMBER, and EXACT: the lexer parses 1.5 as 3/2, and all
;            arithmetic stays rational.  awk's doubles are an implementation
;            detail of C awk; the observable contract is the FORMATTING
;            (%.6g at output), which %awk-num->str reproduces from exact
;            values.  Divergence: float-roundoff artifacts (0.1+0.2 != 0.3
;            territory) do not occur here -- recorded as a pending spec.
;   string   an x string.
;   strnum   (strnum "text" N) -- a value from INPUT that looks numeric.
;            Fields carry these; POSIX's comparison table needs to know a
;            value's provenance, and this tag is that fact.
;   uninit   nil.  "" in string context, 0 in numeric context, false.
;
; PER-RUN STATE IS RESET AT THE ENTRY POINT, never restored at exits (the
; crafting doc's rule: a raise skips your restore).  Everything mutable
; lives in a handful of module globals set! fresh by awk-run.

; --- Run state ---------------------------------------------------------------

(def %awk-genv ())      ; ((name . vbox) ...), newest first
(def %awk-f0 "")        ; the current record's text
(def %awk-fields ())    ; current fields, as values (strnum or string)
(def %awk-fs-cache ())  ; (fs-text . splitter) -- see %awk-split-record
(def %awk-input "")     ; the run's whole input text
(def %awk-recs (lit unread))  ; remaining records; see %awk-recs-force!
(def %awk-funcs ())     ; ((name params . body) ...)

(def %awk-var-box
  (fn (_ name)
    (def go
      (fn (self es)
        (if (null? es) ()
          (if (string=? (first (first es)) name)
            (rest (first es))
            (self (rest es))))))
    (go %awk-genv)))

(def %awk-var-get
  (fn (_ name)
    (def box (%awk-var-box name))
    (if (null? box) () (first box))))

(def %awk-var-set!
  (fn (_ name v)
    (def box (%awk-var-box name))
    (if (null? box)
      (set! %awk-genv (pair (pair name (list v)) %awk-genv))
      (set-first! box v))))

; --- Arrays ------------------------------------------------------------------
; (array BOX) where BOX is a one-cell list holding ((keystr . vbox) ...),
; newest first.  String-keyed by our own str=? scan -- the platform's Assoc
; is identity-keyed.  POSIX semantics carried here: REFERENCING an element
; creates it (uninit), `in` tests WITHOUT creating, subscripts are strings.

(def %awk-array?
  (fn (_ v) (if (pair? v) (eq? (first v) (lit array)) #f)))

(def %awk-array-new (fn (_) (list (lit array) (list ()))))

(def %awk-arr-box (fn (_ arr) (first (rest arr))))

(def %awk-arr-entry
  (fn (_ arr key)
    (def go
      (fn (self es)
        (if (null? es) ()
          (if (string=? (first (first es)) key)
            (first es)
            (self (rest es))))))
    (go (first (%awk-arr-box arr)))))

; The element's value box, created uninit when absent -- the POSIX
; "mentioning a[k] makes it exist" rule, shared by get and set.
(def %awk-arr-ref!
  (fn (_ arr key)
    (def e (%awk-arr-entry arr key))
    (if (null? e)
      (let ((box (%awk-arr-box arr)))
        (def vbox (list ()))
        (set-first! box (pair (pair key vbox) (first box)))
        vbox)
      (rest e))))

(def %awk-arr-has?
  (fn (_ arr key) (not (null? (%awk-arr-entry arr key)))))

(def %awk-arr-del!
  (fn (_ arr key)
    (def box (%awk-arr-box arr))
    (def go
      (fn (self es)
        (if (null? es) ()
          (if (string=? (first (first es)) key)
            (rest es)
            (pair (first es) (self (rest es)))))))
    (set-first! box (go (first box)))))

(def %awk-arr-clear!
  (fn (_ arr) (set-first! (%awk-arr-box arr) ())))

(def %awk-arr-count
  (fn (_ arr) (length (first (%awk-arr-box arr)))))

; Keys in insertion order (entries prepend, so reverse).  for-in order is
; unspecified by POSIX; insertion order is at least deterministic.
(def %awk-arr-keys
  (fn (_ arr) (reverse (map (fn (_ e) (first e)) (first (%awk-arr-box arr))))))

; A variable in ARRAY position: uninit becomes a fresh array in place; a
; scalar is a loud error, awk's own rule.
(def %awk-var-array!
  (fn (_ name)
    (def v (%awk-var-get name))
    (match
      ((%awk-array? v) v)
      ((null? v)
        (let ((a (%awk-array-new)))
          (%awk-var-set! name a)
          a))
      (#t (Err raise (lit awk)
            (string-append "awk: " name " is a scalar, used as an array") ())))))

; --- Coercions ---------------------------------------------------------------

(def %awk-strnum?
  (fn (_ v) (if (pair? v) (eq? (first v) (lit strnum)) #f)))

; Prefix-parse a string as awk does: optional blanks and sign, then the
; lexer's own number scanner.  Answers (value . chars-consumed-through);
; a string with no numeric prefix answers (0 . start).
(def %awk-str-prefix-num
  (fn (_ s)
    (def end (string-length s))
    (def skip-ws
      (fn (self i)
        (if (>= i end) i
          (let ((c (char->integer (string-ref s i))))
            (if (if (= c 32) #t (= c 9)) (self (+ i 1)) i)))))
    (def i0 (skip-ws 0))
    (def neg (if (< i0 end) (= (string-ref s i0) #\-) #f))
    (def i1 (if (< i0 end)
              (let ((c (string-ref s i0)))
                (if (if (= c #\-) #t (= c #\+)) (+ i0 1) i0))
              i0))
    (def digit-at?
      (fn (_ j)
        (if (>= j end) #f
          (%awk-lex-digit? (char->integer (string-ref s j))))))
    (def starts?
      (if (digit-at? i1) #t
        (if (if (< i1 end) (= (string-ref s i1) #\.) #f)
          (digit-at? (+ i1 1))
          #f)))
    (if (not starts?)
      (pair 0 0)
      (let ((r (%awk-lex-num s i1 end)))
        (pair (if neg (- 0 (first (rest (first r)))) (first (rest (first r))))
          (rest r))))))

; Does this input text LOOK numeric in full -- blanks, one number, blanks?
; That is POSIX's strnum test; answers the value or nil.
(def %awk-looks-numeric
  (fn (_ s)
    (def end (string-length s))
    (def skip-ws
      (fn (self i)
        (if (>= i end) i
          (let ((c (char->integer (string-ref s i))))
            (if (if (= c 32) #t (= c 9)) (self (+ i 1)) i)))))
    (def i0 (skip-ws 0))
    (if (>= i0 end) ()
      (let ((neg (= (string-ref s i0) #\-)))
        (def i1 (let ((c (string-ref s i0)))
                  (if (if (= c #\-) #t (= c #\+)) (+ i0 1) i0)))
        (def digit-at?
          (fn (_ j)
            (if (>= j end) #f
              (%awk-lex-digit? (char->integer (string-ref s j))))))
        (if (not (if (digit-at? i1) #t
                   (if (if (< i1 end) (= (string-ref s i1) #\.) #f)
                     (digit-at? (+ i1 1)) #f)))
          ()
          (let ((r (%awk-lex-num s i1 end)))
            (if (= (skip-ws (rest r)) end)
              (if neg (- 0 (first (rest (first r)))) (first (rest (first r))))
              ())))))))

; Wrap one piece of INPUT text as a value: strnum when it looks numeric.
(def %awk-input-val
  (fn (_ text)
    (def n (%awk-looks-numeric text))
    (if (null? n) text (list (lit strnum) text n))))

(def %awk-to-num
  (fn (_ v)
    (match
      ((null? v) 0)
      ((number? v) v)
      ((%awk-strnum? v) (first (rest (rest v))))
      ((%awk-array? v)
        (Err raise (lit awk) "awk: array used in scalar context" ()))
      (#t (first (%awk-str-prefix-num v))))))

; --- Number formatting: %.6g from exact values -------------------------------

; trunc toward zero, via the probed fact that (% x 1) answers the
; fractional part for a non-negative rational.  The (+ 0 ...) is load-
; bearing: the tower's SUBTRACT can answer a denominator-1 rational
; (1/1) without demoting it to an int at large denominators, and a
; digit loop that then computes (+ 48 d) hands integer->char a rational
; -- garbage bytes in the output.  ADD normalizes; measured, not
; reasoned (the probes are in the suite's history).
(def %awk-trunc
  (fn (_ x)
    (+ 0
      (if (< x 0) (- 0 (- (- 0 x) (% (- 0 x) 1))) (- x (% x 1))))))

(def %awk-int->str
  (fn (_ n)
    (if (= n 0) "0"
      (let ((digits ()))
        (def go
          (fn (self t acc)
            (if (= t 0) acc
              (self (/ (- t (% t 10)) 10)
                (pair (integer->char (+ 48 (% t 10))) acc)))))
        (if (< n 0)
          (string-append "-" (list->string (go (- 0 n) ())))
          (list->string (go n ())))))))

; Number to string: integral values are always plain integers (POSIX);
; everything else goes through the printf engine with CONVFMT -- %.6g by
; default, e-notation included.  The engine lives in awk/fmt.x; the
; reference resolves at call time, so file order does not matter.
(def %awk-num->str
  (fn (_ n)
    (if (= 0 (% n 1))
      (%awk-int->str n)
      (let ((f (%awk-var-get "CONVFMT")))
        (%awk-sprintf (if (null? f) "%.6g" (%awk-to-str f)) (list n))))))

(def %awk-to-str
  (fn (_ v)
    (match
      ((null? v) "")
      ((number? v) (%awk-num->str v))
      ((%awk-strnum? v) (first (rest v)))
      ((%awk-array? v)
        (Err raise (lit awk) "awk: array used in scalar context" ()))
      (#t v))))

; --- Truth and comparison ----------------------------------------------------

(def %awk-truthy?
  (fn (_ v)
    (match
      ((null? v) #f)
      ((number? v) (not (= v 0)))
      ((%awk-strnum? v) (not (= (first (rest (rest v))) 0)))
      (#t (> (string-length v) 0)))))

(def %awk-str-cmp
  (fn (_ a b)
    (def la (string-length a))
    (def lb (string-length b))
    (def go
      (fn (self i)
        (if (>= i la) (if (>= i lb) 0 (- 0 1))
          (if (>= i lb) 1
            (let ((ca (char->integer (string-ref a i)))
                  (cb (char->integer (string-ref b i))))
              (if (< ca cb) (- 0 1)
                (if (> ca cb) 1 (self (+ i 1)))))))))
    (go 0)))

; POSIX comparison: numeric when both sides are numeric-ish (a number, a
; strnum, or uninit); string otherwise.  A string CONSTANT on either side
; forces a string comparison -- "10" < "9" is true, $1 < $2 on the same
; input is not.
(def %awk-numish?
  (fn (_ v)
    (if (null? v) #t (if (number? v) #t (%awk-strnum? v)))))

(def %awk-cmp
  (fn (_ a b)
    (if (if (%awk-numish? a) (%awk-numish? b) #f)
      (let ((x (%awk-to-num a)) (y (%awk-to-num b)))
        (if (< x y) (- 0 1) (if (> x y) 1 0)))
      (%awk-str-cmp (%awk-to-str a) (%awk-to-str b)))))

(def %awk-bool (fn (_ b) (if b 1 0)))

; --- Fields ------------------------------------------------------------------

; Split one record by the current FS.  Three regimes, POSIX's own:
;   FS = " "     runs of blanks separate, leading/trailing ignored
;   FS = one c   that character, literally
;   FS = other   an ERE, compiled once and cached
(def %awk-split-char
  (fn (_ s c)
    (def end (string-length s))
    (def go
      (fn (self i start acc)
        (if (>= i end)
          (reverse (pair (substring s start end) acc))
          (if (= (string-ref s i) c)
            (self (+ i 1) (+ i 1) (pair (substring s start i) acc))
            (self (+ i 1) start acc)))))
    (go 0 0 ())))

(def %awk-blank?
  (fn (_ c)
    (let ((ci (char->integer c)))
      (if (= ci 32) #t (if (= ci 9) #t (= ci 10))))))

(def %awk-split-blanks
  (fn (_ s)
    (def end (string-length s))
    (def skip
      (fn (self i)
        (if (>= i end) i
          (if (%awk-blank? (string-ref s i)) (self (+ i 1)) i))))
    (def word
      (fn (self i)
        (if (>= i end) i
          (if (%awk-blank? (string-ref s i)) i (self (+ i 1))))))
    (def go
      (fn (self i acc)
        (let ((st (skip i)))
          (if (>= st end) (reverse acc)
            (let ((en (word st)))
              (self en (pair (substring s st en) acc)))))))
    (go 0 ())))

; Split text by a separator STRING, POSIX's three regimes.  An empty text
; has no fields at all -- an empty record answers NF=0 whatever FS says,
; and split("", a) answers 0.
(def %awk-split-by
  (fn (_ text fs)
    (match
      ((= (string-length text) 0) ())
      ((string=? fs " ") (%awk-split-blanks text))
      ((= (string-length fs) 1)
        (%awk-split-char text (string-ref fs 0)))
      (#t
        (let ((rx (if (if (pair? %awk-fs-cache)
                        (string=? (first %awk-fs-cache) fs) #f)
                    (rest %awk-fs-cache)
                    (let ((c (regex-compile fs)))
                      (set! %awk-fs-cache (pair fs c))
                      c))))
          (regex-split text rx))))))

(def %awk-split-record
  (fn (_ rec)
    (def fs (%awk-to-str (%awk-var-get "FS")))
    (map (fn (_ t) (%awk-input-val t))
      ; paragraph mode (RS=""): a newline separates fields ALWAYS, on
      ; top of whatever FS says -- POSIX's one field-splitting override.
      (if (string=? (%awk-to-str (%awk-var-get "RS")) "")
        (let ((lines (%awk-split-char rec #\newline)))
          (def flat
            (fn (self ls)
              (if (null? ls) ()
                (append (%awk-split-by (first ls) fs) (self (rest ls))))))
          (flat lines))
        (%awk-split-by rec fs)))))

; split(s, a [, fs]) -- the array argument arrives as an AST node because
; it passes BY NAME: the parser hands the nodes over unevaluated and this
; is the one builtin that wants them so.  A /re/ third argument uses its
; compiled regex; a string third argument follows the FS regimes; absent,
; the current FS applies.
(def %awk-split-call
  (fn (_ arg-nodes)
    (def s (%awk-to-str (%awk-eval (first arg-nodes))))
    (def arr-node (first (rest arg-nodes)))
    (if (not (eq? (first arr-node) (lit var)))
      (Err raise (lit awk) "awk: split needs an array name" ())
      (let ((arr (%awk-var-array! (first (rest arr-node)))))
        (%awk-arr-clear! arr)
        (def fs-node (if (null? (rest (rest arg-nodes))) ()
                       (first (rest (rest arg-nodes)))))
        (def texts
          (match
            ((null? fs-node)
              (%awk-split-by s (%awk-to-str (%awk-var-get "FS"))))
            ((eq? (first fs-node) (lit ere))
              (if (= (string-length s) 0) ()
                (regex-split s (first (rest fs-node)))))
            (#t (%awk-split-by s (%awk-to-str (%awk-eval fs-node))))))
        (def go
          (fn (self ts i)
            (if (null? ts) (- i 1)
              (do (set-first! (%awk-arr-ref! arr (%awk-int->str i))
                    (%awk-input-val (first ts)))
                  (self (rest ts) (+ i 1))))))
        (go texts 1)))))

; sub(re, repl [, target]) and gsub -- replace in place, answer the count.
; The target passes BY NAME like split's array: it must be an l-value
; (default $0), and the write goes through %awk-lval-set!, so a field
; target rebuilds $0 exactly as a plain field assignment would.  In repl,
; & is the matched text, \& a literal &, \\ a backslash -- awk's rules,
; NOT the $N expansion Regex replace-all carries, which is why the loop
; lives here instead of riding that method.
(def %awk-sub-expand
  (fn (_ repl matched)
    (def end (string-length repl))
    (def go
      (fn (self i acc)
        (if (>= i end) (string-concat (reverse acc))
          (let ((c (string-ref repl i)))
            (match
              ((= c #\&) (self (+ i 1) (pair matched acc)))
              ((if (= c #\\) (< (+ i 1) end) #f)
                (let ((e (string-ref repl (+ i 1))))
                  (if (if (= e #\&) #t (= e #\\))
                    (self (+ i 2) (pair (substring repl (+ i 1) (+ i 2)) acc))
                    (self (+ i 1) (pair "\\" acc)))))
              (#t (self (+ i 1) (pair (substring repl i (+ i 1)) acc))))))))
    (go 0 ())))

; match(s, re): RSTART/RLENGTH always set, RSTART (1-based, 0 = none)
; answered.  The re argument is a NODE for the same reason sub's is: an
; ERE literal must reach here as its compiled regex, not as the 0/1 of
; a match against $0.
(def %awk-match-call
  (fn (_ nodes)
    (def s (%awk-to-str (%awk-eval (first nodes))))
    (def rx (%awk-match-rx (first (rest nodes))))
    (def m (regex-search s rx))
    (if (null? m)
      (do (%awk-var-set! "RSTART" 0)
          (%awk-var-set! "RLENGTH" (- 0 1))
          0)
      (do (%awk-var-set! "RSTART" (+ 1 (first m)))
          (%awk-var-set! "RLENGTH" (- (first (rest m)) (first m)))
          (+ 1 (first m))))))

(def %awk-sub-call
  (fn (_ global? nodes)
    (def rx (%awk-match-rx (first nodes)))
    (def repl (%awk-to-str (%awk-eval (first (rest nodes)))))
    (def target
      (if (null? (rest (rest nodes)))
        (list (lit field) (list (lit num) 0))
        (first (rest (rest nodes)))))
    (if (not (%awk-p-lval? target))
      (Err raise (lit awk) "awk: sub/gsub target must be assignable" ())
      (let ((s (%awk-to-str (%awk-lval-get target))))
        (def len (string-length s))
        ; An empty match replaces, keeps the next character, and steps
        ; past it -- gsub(/x*/, "-", "abc") is "-a-b-c-", count 4.
        (def go
          (fn (self pos pieces count)
            (def m (if (> pos len) () (regex-find-at s pos rx)))
            (if (null? m)
              (pair count
                (string-concat
                  (reverse (pair (substring s pos len) pieces))))
              (let ((st (first m)))
                (def en (first (rest m)))
                (def hit
                  (pair (%awk-sub-expand repl (substring s st en))
                    (pair (substring s pos st) pieces)))
                (match
                  ((not global?)
                    (pair (+ count 1)
                      (string-concat
                        (reverse (pair (substring s en len) hit)))))
                  ((= st en)
                    (if (>= en len)
                      (pair (+ count 1) (string-concat (reverse hit)))
                      (self (+ en 1)
                        (pair (substring s en (+ en 1)) hit)
                        (+ count 1))))
                  (#t (self en hit (+ count 1))))))))
        (def r (go 0 () 0))
        (if (> (first r) 0)
          (%awk-lval-set! target (rest r))
          ())
        (first r)))))

(def %awk-set-record!
  (fn (_ rec)
    (set! %awk-f0 rec)
    (set! %awk-fields (%awk-split-record rec))
    (%awk-var-set! "NF" (length %awk-fields))))

(def %awk-field-get
  (fn (_ idx)
    (def i (%awk-trunc idx))
    (match
      ((= i 0) (%awk-input-val %awk-f0))
      ((< i 0) (Err raise (lit awk) "awk: negative field index" i))
      ((> i (length %awk-fields)) ())
      (#t (nth (- i 1) %awk-fields)))))

; --- Field assignment --------------------------------------------------------
; POSIX's rebuild rules: assigning any $i (or NF) reconstructs $0 by
; joining the fields with OFS at that moment; assigning past NF fills the
; gap with empty strings; assigning $0 re-splits per FS.  The assigned
; VALUE is stored as it is -- a number stays a number, and renders through
; CONVFMT only when $0 is rebuilt.

(def %awk-join-fields
  (fn (_ vals ofs)
    (def go
      (fn (self vs)
        (if (null? vs) ()
          (pair (%awk-to-str (first vs))
            (if (null? (rest vs)) ()
              (pair ofs (self (rest vs))))))))
    (string-concat (go vals))))

(def %awk-rebuild-record!
  (fn (_)
    (set! %awk-f0
      (%awk-join-fields %awk-fields (%awk-to-str (%awk-var-get "OFS"))))
    (%awk-var-set! "NF" (length %awk-fields))))

; The field list with slot i (1-based) holding v, gaps filled with "".
(def %awk-fields-put
  (fn (_ lst i v)
    (def go
      (fn (self l k)
        (if (= k 1)
          (pair v (if (null? l) () (rest l)))
          (pair (if (null? l) "" (first l))
            (self (if (null? l) () (rest l)) (- k 1))))))
    (go lst i)))

; The field list resized to exactly n slots, "" filling any growth.
(def %awk-fields-resize
  (fn (_ lst n)
    (def go
      (fn (self l k)
        (if (<= k 0) ()
          (pair (if (null? l) "" (first l))
            (self (if (null? l) () (rest l)) (- k 1))))))
    (go lst n)))

(def %awk-field-set!
  (fn (_ idx v)
    (def i (%awk-trunc idx))
    (match
      ((< i 0) (Err raise (lit awk) "awk: negative field index" i))
      ((= i 0) (%awk-set-record! (%awk-to-str v)))
      (#t
        (do (set! %awk-fields (%awk-fields-put %awk-fields i v))
            (%awk-rebuild-record!))))))

(def %awk-set-nf!
  (fn (_ n)
    (if (< n 0)
      (Err raise (lit awk) "awk: NF set negative" n)
      (do (set! %awk-fields (%awk-fields-resize %awk-fields n))
          (%awk-rebuild-record!)))))

; --- Builtins ----------------------------------------------------------------

(def %awk-str-index
  (fn (_ s t)
    (def ls (string-length s))
    (def lt (string-length t))
    (def hit?
      (fn (self i j)
        (if (>= j lt) #t
          (if (= (string-ref s (+ i j)) (string-ref t j))
            (self i (+ j 1))
            #f))))
    (def go
      (fn (self i)
        (if (> (+ i lt) ls) 0
          (if (hit? i 0) (+ i 1) (self (+ i 1))))))
    (go 0)))

; --- The float boundary and the PRNG -----------------------------------------
; A libm result comes back as its printed digits re-read into a rational,
; so floats never leak into the value model.  CAPPED AT 10 SIGNIFICANT
; DIGITS, and the cap is load-bearing: the engine's rational arithmetic
; silently corrupts somewhere past ~1e13-denominator operands (measured:
; frac*1e5 + 1/2 on a 14-digit mantissa answered a wrong, non-integral
; rational; the probes are in the suite's history).  Ten digits keeps
; every formatter intermediate far inside the safe regime while carrying
; 100x more precision than %.6g renders.  Digits past the tenth become
; zeros -- position preserved, so magnitude survives and fraction tails
; reduce away.
(def %awk-float->rat
  (fn (_ f)
    (def s (float->string f))
    (def end (string-length s))
    (def go
      (fn (self i sig started acc)
        (if (>= i end) (list->string (reverse acc))
          (let ((c (string-ref s i)))
            (def ci (char->integer c))
            (match
              ; exponent marker: the tail is magnitude, copy it verbatim
              ((if (= c #\e) #t (= c #\E))
                (let ((copy ()))
                  (set! copy
                    (fn (self2 j acc2)
                      (if (>= j end) (list->string (reverse acc2))
                        (self2 (+ j 1) (pair (string-ref s j) acc2)))))
                  (copy i acc)))
              ((%awk-lex-digit? ci)
                (let ((live (if started #t (not (= ci 48)))))
                  (def sig2 (if live (+ sig 1) sig))
                  (self (+ i 1) sig2 live
                    (pair (if (if live (> sig2 10) #f) #\0 c) acc))))
              (#t (self (+ i 1) sig started (pair c acc))))))))
    (first (%awk-str-prefix-num (go 0 0 #f ())))))

(def %awk-math-1
  (fn (_ op v) (%awk-float->rat (op (float-from (%awk-to-num v))))))

; rand state: xorshift behind srand's seed protocol.  srand() with no
; argument reseeds with the previous seed here (C awk uses time of day;
; a pure core has no clock, and determinism is the better default).
(def %awk-rng ())
(def %awk-seed 0)

(def %awk-srand!
  (fn (_ seed)
    (def prev %awk-seed)
    (set! %awk-seed seed)
    (set! %awk-rng (make-rng seed))
    prev))

(def %awk-rand
  (fn (_)
    (/ (rng-int %awk-rng 2147483648) 2147483648)))

; Case mapping, ASCII: the byte-string model's honest span.
(def %awk-mapcase
  (fn (_ s up?)
    (def end (string-length s))
    (def go
      (fn (self i acc)
        (if (>= i end) (list->string (reverse acc))
          (let ((ci (char->integer (string-ref s i))))
            (def co
              (if up?
                (if (if (>= ci 97) (<= ci 122) #f) (- ci 32) ci)
                (if (if (>= ci 65) (<= ci 90) #f) (+ ci 32) ci)))
            (self (+ i 1) (pair (integer->char co) acc))))))
    (go 0 ())))

(def %awk-builtin
  (fn (_ name args)
    (match
      ((string=? name "length")
        ; length(a) on an array is its element count (POSIX 2008).
        (if (if (pair? args) (%awk-array? (first args)) #f)
          (%awk-arr-count (first args))
          (string-length
            (if (null? args) %awk-f0 (%awk-to-str (first args))))))
      ((string=? name "index")
        (%awk-str-index (%awk-to-str (first args))
          (%awk-to-str (first (rest args)))))
      ((string=? name "sprintf")
        (%awk-sprintf (%awk-to-str (first args)) (rest args)))
      ((string=? name "toupper") (%awk-mapcase (%awk-to-str (first args)) #t))
      ((string=? name "tolower") (%awk-mapcase (%awk-to-str (first args)) #f))
      ((string=? name "sin") (%awk-math-1 float-sin (first args)))
      ((string=? name "cos") (%awk-math-1 float-cos (first args)))
      ((string=? name "exp") (%awk-math-1 float-exp (first args)))
      ((string=? name "log") (%awk-math-1 float-log (first args)))
      ((string=? name "sqrt") (%awk-math-1 float-sqrt (first args)))
      ((string=? name "atan2")
        (%awk-float->rat
          (float-atan2 (float-from (%awk-to-num (first args)))
            (float-from (%awk-to-num (first (rest args)))))))
      ((string=? name "rand") (%awk-rand))
      ((string=? name "srand")
        (%awk-srand!
          (if (null? args) %awk-seed (%awk-trunc (%awk-to-num (first args))))))
      ((string=? name "int")
        (%awk-trunc (%awk-to-num (first args))))
      ((string=? name "substr")
        (let ((s (%awk-to-str (first args))))
          (def len (string-length s))
          ; POSIX: 1-based start m, optional count n; the window is
          ; clamped to the string, and a start below 1 eats into n.
          (def m (%awk-trunc (%awk-to-num (first (rest args)))))
          (def n (if (null? (rest (rest args)))
                   len
                   (%awk-trunc (%awk-to-num (first (rest (rest args)))))))
          (def from (if (< m 1) 0 (- m 1)))
          (def upto (+ (- m 1) n))
          (def to (if (> upto len) len (if (< upto 0) 0 upto)))
          (if (>= from to) "" (substring s from to))))
      (#t (Err raise (lit awk)
            (string-append "awk: unknown function " name) ())))))

; --- Expressions -------------------------------------------------------------

(def %awk-eval ())

; The regex for a match operand: an ERE node carries one compiled; any
; other expression is a DYNAMIC regex -- its string compiles here.
(def %awk-match-rx
  (fn (_ node)
    (if (eq? (first node) (lit ere))
      (first (rest node))
      (regex-compile (%awk-to-str (%awk-eval node))))))

; One key from a subscript list: each subscript renders as a string, and
; multiple join with SUBSEP -- POSIX's one-key reading of a[i,j].
(def %awk-subs-key
  (fn (_ subs)
    (def texts (map (fn (_ e) (%awk-to-str (%awk-eval e))) subs))
    (if (null? (rest texts))
      (first texts)
      (let ((sep (%awk-to-str (%awk-var-get "SUBSEP"))))
        (def go
          (fn (self ts)
            (if (null? (rest ts)) (first ts)
              (string-append (first ts) sep (self (rest ts))))))
        (go texts)))))

(def %awk-lval-get
  (fn (_ lv)
    (match
      ((eq? (first lv) (lit var)) (%awk-var-get (first (rest lv))))
      ((eq? (first lv) (lit index))
        (first (%awk-arr-ref! (%awk-var-array! (first (rest lv)))
                 (%awk-subs-key (first (rest (rest lv)))))))
      (#t (%awk-field-get (%awk-to-num (%awk-eval (first (rest lv)))))))))

(def %awk-lval-set!
  (fn (_ lv v)
    (match
      ((eq? (first lv) (lit var))
        ; NF is live: assigning it resizes the fields and rebuilds $0.
        (if (string=? (first (rest lv)) "NF")
          (%awk-set-nf! (%awk-trunc (%awk-to-num v)))
          (%awk-var-set! (first (rest lv)) v)))
      ((eq? (first lv) (lit index))
        (set-first!
          (%awk-arr-ref! (%awk-var-array! (first (rest lv)))
            (%awk-subs-key (first (rest (rest lv)))))
          v))
      (#t (%awk-field-set! (%awk-to-num (%awk-eval (first (rest lv)))) v)))))

(def %awk-incr!
  (fn (_ lv delta pre?)
    (def old (%awk-to-num (%awk-lval-get lv)))
    (def new (+ old delta))
    (%awk-lval-set! lv new)
    (if pre? new old)))

; A user function call.  awk's scoping: parameters are the ONLY locals
; (extras beyond the arguments start uninit), everything else is global.
; Dynamic save/restore carries that -- and because an unbound variable
; already reads as uninit (), "restore" is just writing the old VALUE
; back, whether or not the name existed.  An array argument binds the
; array OBJECT itself, which is pass-by-reference for free.  A raise out
; of the body skips the restore; per-run state resets at awk-run, the
; crafting doc's line on where restores belong.
(def %awk-ucall
  (fn (_ nm arg-nodes)
    (def find
      (fn (self fs)
        (if (null? fs) ()
          (if (string=? (first (first fs)) nm)
            (first fs)
            (self (rest fs))))))
    (def f (find %awk-funcs))
    (if (null? f)
      (Err raise (lit awk)
        (string-append "awk: calling undefined function " nm) ())
      (let ((params (first (rest f))))
        (def body (rest (rest f)))
        (def args (map (fn (_ a) (%awk-eval a)) arg-nodes))
        (if (> (length args) (length params))
          (Err raise (lit awk)
            (string-append "awk: too many arguments to " nm) ())
          (let ((saved (map (fn (_ p) (pair p (%awk-var-get p))) params)))
            (def bind
              (fn (self ps as)
                (unless (null? ps)
                  (%awk-var-set! (first ps) (if (null? as) () (first as)))
                  (self (rest ps) (if (null? as) () (rest as))))))
            (bind params args)
            (def c (%awk-exec-list body))
            (map (fn (_ sv) (%awk-var-set! (first sv) (rest sv))) saved)
            (match
              ((null? c) ())
              ((eq? (first c) (lit return)) (first (rest c)))
              (#t (Err raise (lit awk)
                    "awk: next/break/continue/exit cannot escape a function"
                    ())))))))))

(set! %awk-eval
  (fn (_ node)
    (def tag (first node))
    (match
      ((eq? tag (lit num)) (first (rest node)))
      ((eq? tag (lit str)) (first (rest node)))
      ; a bare /ere/ in expression position asks: does $0 match?
      ((eq? tag (lit ere))
        (%awk-bool (not (null? (regex-search %awk-f0 (first (rest node)))))))
      ((eq? tag (lit var)) (%awk-var-get (first (rest node))))
      ((eq? tag (lit field))
        (%awk-field-get (%awk-to-num (%awk-eval (first (rest node))))))
      ; a[k]: the shared l-value path -- which CREATES the element,
      ; POSIX's rule for mentioning a subscript.
      ((eq? tag (lit index)) (%awk-lval-get node))
      ; (k in a): membership WITHOUT creating -- the counterpart rule.
      ((eq? tag (lit in))
        (let ((av (%awk-var-get (first (rest (rest node))))))
          (%awk-bool
            (if (%awk-array? av)
              (%awk-arr-has? av (%awk-to-str (%awk-eval (first (rest node)))))
              #f))))
      ((eq? tag (lit assign))
        (let ((v (%awk-eval (first (rest (rest node))))))
          (if (%awk-array? v)
            (Err raise (lit awk) "awk: an array cannot be assigned" ())
            (do (%awk-lval-set! (first (rest node)) v) v))))
      ((eq? tag (lit bin))
        (let ((op (first (rest node))))
          (def a (%awk-to-num (%awk-eval (first (rest (rest node))))))
          (def b (%awk-to-num (%awk-eval (first (rest (rest (rest node)))))))
          (match
            ((string=? op "+") (+ a b))
            ((string=? op "-") (- a b))
            ((string=? op "*") (* a b))
            ((string=? op "/") (/ a b))
            ; awk's % is fmod: exact here, sign follows the dividend.
            ((string=? op "%") (- a (* b (%awk-trunc (/ a b)))))
            (#t (Err raise (lit awk) "awk: unknown operator" op)))))
      ((eq? tag (lit pow))
        (let ((a (%awk-to-num (%awk-eval (first (rest node))))))
          (def e (%awk-to-num (%awk-eval (first (rest (rest node))))))
          (if (not (= 0 (% e 1)))
            (Err raise (lit awk)
              "awk: fractional exponents are not built yet (exact core)" e)
            (let ((go ()))
              (set! go
                (fn (self k acc)
                  (if (= k 0) acc (self (- k 1) (* acc a)))))
              (if (< e 0) (/ 1 (go (- 0 e) 1)) (go e 1))))))
      ((eq? tag (lit neg)) (- 0 (%awk-to-num (%awk-eval (first (rest node))))))
      ((eq? tag (lit not))
        (%awk-bool (not (%awk-truthy? (%awk-eval (first (rest node)))))))
      ((eq? tag (lit concat))
        (string-append (%awk-to-str (%awk-eval (first (rest node))))
          (%awk-to-str (%awk-eval (first (rest (rest node)))))))
      ((eq? tag (lit cmp))
        (let ((op (first (rest node))))
          (def c (%awk-cmp (%awk-eval (first (rest (rest node))))
                   (%awk-eval (first (rest (rest (rest node)))))))
          (%awk-bool
            (match
              ((string=? op "<") (< c 0))
              ((string=? op "<=") (<= c 0))
              ((string=? op ">") (> c 0))
              ((string=? op ">=") (>= c 0))
              ((string=? op "==") (= c 0))
              (#t (not (= c 0)))))))
      ((eq? tag (lit match))
        (%awk-bool
          (not (null?
            (regex-search (%awk-to-str (%awk-eval (first (rest node))))
              (%awk-match-rx (first (rest (rest node)))))))))
      ((eq? tag (lit nomatch))
        (%awk-bool
          (null?
            (regex-search (%awk-to-str (%awk-eval (first (rest node))))
              (%awk-match-rx (first (rest (rest node))))))))
      ((eq? tag (lit and))
        (%awk-bool
          (if (%awk-truthy? (%awk-eval (first (rest node))))
            (%awk-truthy? (%awk-eval (first (rest (rest node)))))
            #f)))
      ((eq? tag (lit or))
        (%awk-bool
          (if (%awk-truthy? (%awk-eval (first (rest node))))
            #t
            (%awk-truthy? (%awk-eval (first (rest (rest node))))))))
      ((eq? tag (lit ternary))
        (if (%awk-truthy? (%awk-eval (first (rest node))))
          (%awk-eval (first (rest (rest node))))
          (%awk-eval (first (rest (rest (rest node)))))))
      ((eq? tag (lit ucall))
        (%awk-ucall (first (rest node)) (first (rest (rest node)))))
      ; getline [var]: the next main-input record.  Bare getline is a
      ; full record swap ($0, NF); the var form stores the text only.
      ; Both count NR.  1 on a record, 0 at end of input.
      ((eq? tag (lit getline))
        (let ((rec (%awk-next-record!)))
          (if (eq? rec (lit eof)) 0
            (do (if (null? (first (rest node)))
                  (%awk-set-record! rec)
                  (%awk-lval-set! (first (rest node)) (%awk-input-val rec)))
                1))))
      ((eq? tag (lit preinc)) (%awk-incr! (first (rest node)) 1 #t))
      ((eq? tag (lit postinc)) (%awk-incr! (first (rest node)) 1 #f))
      ((eq? tag (lit predec)) (%awk-incr! (first (rest node)) (- 0 1) #t))
      ((eq? tag (lit postdec)) (%awk-incr! (first (rest node)) (- 0 1) #f))
      ((eq? tag (lit call))
        (let ((nm (first (rest node))))
          (match
            ((string=? nm "split")
              (%awk-split-call (first (rest (rest node)))))
            ((string=? nm "sub")
              (%awk-sub-call #f (first (rest (rest node)))))
            ((string=? nm "gsub")
              (%awk-sub-call #t (first (rest (rest node)))))
            ((string=? nm "match")
              (%awk-match-call (first (rest (rest node)))))
            (#t
              (%awk-builtin nm
                (map (fn (_ a) (%awk-eval a)) (first (rest (rest node)))))))))
      (#t (Err raise (lit awk) "awk: unknown expression" tag)))))

; --- Statements --------------------------------------------------------------
; A statement answers a CONTROL: nil to carry on, or (next) (break)
; (continue) (exit V) travelling up until something consumes it.

(def %awk-exec ())

(def %awk-exec-list
  (fn (self stmts)
    (if (null? stmts) ()
      (let ((c (%awk-exec (first stmts))))
        (if (null? c) (self (rest stmts)) c)))))

; What print shows for a value: like %awk-to-str, but a non-integral
; number renders through OFMT where conversions use CONVFMT -- POSIX's
; one deliberate asymmetry between output and conversion.
(def %awk-out-str
  (fn (_ v)
    (if (number? v)
      (if (= 0 (% v 1))
        (%awk-int->str v)
        (let ((f (%awk-var-get "OFMT")))
          (%awk-sprintf (if (null? f) "%.6g" (%awk-to-str f)) (list v))))
      (%awk-to-str v))))

(def %awk-print!
  (fn (_ args)
    (def ofs (%awk-to-str (%awk-var-get "OFS")))
    (def go
      (fn (self as first?)
        (unless (null? as)
          (unless first? (display ofs))
          (display (%awk-out-str (%awk-eval (first as))))
          (self (rest as) #f))))
    (if (null? args)
      (display %awk-f0)
      (go args #t))
    (display (%awk-to-str (%awk-var-get "ORS")))))

; MATCH CLAUSES ARE SINGLE-BODY, and a statement's value is its CONTROL:
; every clause here wraps side effects in (do ... ()) so an expression's
; value -- an assignment answers what it assigned -- can never leak out as
; a control and abort the enclosing block.  Both halves of that were
; found the hard way; the probes live in the suite's history.
(set! %awk-exec
  (fn (_ stmt)
    (def tag (first stmt))
    (match
      ((eq? tag (lit print)) (do (%awk-print! (rest stmt)) ()))
      ((eq? tag (lit printf))
        (do (display
              (%awk-sprintf (%awk-to-str (%awk-eval (first (rest stmt))))
                (map (fn (_ a) (%awk-eval a)) (rest (rest stmt)))))
            ()))
      ((eq? tag (lit expr)) (do (%awk-eval (first (rest stmt))) ()))
      ((eq? tag (lit block)) (%awk-exec-list (first (rest stmt))))
      ((eq? tag (lit if))
        (if (%awk-truthy? (%awk-eval (first (rest stmt))))
          (%awk-exec (first (rest (rest stmt))))
          (let ((e (first (rest (rest (rest stmt))))))
            (if (null? e) () (%awk-exec e)))))
      ((eq? tag (lit while))
        (let ((loop ()))
          (set! loop
            (fn (self)
              (if (%awk-truthy? (%awk-eval (first (rest stmt))))
                (let ((c (%awk-exec (first (rest (rest stmt))))))
                  (match
                    ((null? c) (self))
                    ((eq? (first c) (lit break)) ())
                    ((eq? (first c) (lit continue)) (self))
                    (#t c)))
                ())))
          (loop)))
      ((eq? tag (lit do))
        (let ((loop ()))
          (set! loop
            (fn (self)
              (let ((c (%awk-exec (first (rest stmt)))))
                (match
                  ((if (null? c) #f (eq? (first c) (lit break))) ())
                  ((if (null? c) #t (eq? (first c) (lit continue)))
                    (if (%awk-truthy?
                          (%awk-eval (first (rest (rest stmt)))))
                      (self) ()))
                  (#t c)))))
          (loop)))
      ((eq? tag (lit for))
        (let ((init (first (rest stmt))))
          (def c-node (first (rest (rest stmt))))
          (def u-node (first (rest (rest (rest stmt)))))
          (def body (first (rest (rest (rest (rest stmt))))))
          (unless (null? init) (%awk-eval init))
          (let ((loop ()))
            (set! loop
              (fn (self)
                (if (if (null? c-node) #t
                      (%awk-truthy? (%awk-eval c-node)))
                  (let ((c (%awk-exec body)))
                    (match
                      ((if (null? c) #f (eq? (first c) (lit break))) ())
                      ((if (null? c) #t (eq? (first c) (lit continue)))
                        (do (unless (null? u-node) (%awk-eval u-node))
                            (self)))
                      (#t c)))
                  ())))
            (loop))))
      ((eq? tag (lit for-in))
        (let ((vname (first (rest stmt))))
          (def av (%awk-var-get (first (rest (rest stmt)))))
          (def body (first (rest (rest (rest stmt)))))
          (match
            ((null? av) ())   ; nothing to walk
            ((%awk-array? av)
              ; a SNAPSHOT of the keys: the body may delete or add
              ; entries without disturbing this walk.  The key arrives
              ; as input-shaped (strnum when numeric) -- k==10 works.
              (let ((walk ()))
                (set! walk
                  (fn (self ks)
                    (if (null? ks) ()
                      (do (%awk-var-set! vname (%awk-input-val (first ks)))
                          (let ((c (%awk-exec body)))
                            (match
                              ((null? c) (self (rest ks)))
                              ((eq? (first c) (lit break)) ())
                              ((eq? (first c) (lit continue)) (self (rest ks)))
                              (#t c)))))))
                (walk (%awk-arr-keys av))))
            (#t (Err raise (lit awk)
                  "awk: for-in over a scalar" ())))))
      ((eq? tag (lit delete))
        (do (let ((av (%awk-var-get (first (rest stmt)))))
              (def subs (first (rest (rest stmt))))
              (if (%awk-array? av)
                (if (null? subs)
                  (%awk-arr-clear! av)
                  (%awk-arr-del! av (%awk-subs-key subs)))
                ()))
            ()))
      ((eq? tag (lit next)) (list (lit next)))
      ((eq? tag (lit break)) (list (lit break)))
      ((eq? tag (lit continue)) (list (lit continue)))
      ((eq? tag (lit exit))
        (list (lit exit)
          (if (null? (first (rest stmt))) 0
            (%awk-to-num (%awk-eval (first (rest stmt)))))))
      ((eq? tag (lit return))
        (list (lit return)
          (if (null? (first (rest stmt))) ()
            (%awk-eval (first (rest stmt))))))
      (#t (Err raise (lit awk) "awk: unknown statement" tag)))))

; --- The record loop ---------------------------------------------------------

; Paragraph mode: records are runs of non-blank lines; blank lines
; between, before, and after are separators, never records.
(def %awk-para-records
  (fn (_ input)
    (def lines (%awk-split-char input #\newline))
    (def join
      (fn (self ls)
        (if (null? (rest ls)) (first ls)
          (string-append (first ls) (string-append "\n" (self (rest ls)))))))
    (def go
      (fn (self ls run acc)
        (if (null? ls)
          (reverse (if (null? run) acc (pair (join (reverse run)) acc)))
          (if (= (string-length (first ls)) 0)
            (self (rest ls) ()
              (if (null? run) acc (pair (join (reverse run)) acc)))
            (self (rest ls) (pair (first ls) run) acc)))))
    (go lines () ())))

; Records per RS: "" is paragraph mode; otherwise the FIRST character of
; RS separates (POSIX leaves multi-character RS unspecified; first-char
; is the one-true-awk reading).  A trailing separator closes the last
; record rather than opening an empty one.
(def %awk-records
  (fn (_ input)
    (def rs (%awk-to-str (%awk-var-get "RS")))
    (if (string=? rs "")
      (%awk-para-records input)
      (let ((c (string-ref rs 0)))
        (def all (%awk-split-char input c))
        (def drop-last
          (fn (self l)
            (if (null? (rest l)) () (pair (first l) (self (rest l))))))
        (if (null? all) ()
          (if (= (string-length input) 0) ()
            (if (= (string-ref input (- (string-length input) 1)) c)
              (drop-last all)
              all)))))))

; The record stream materializes on FIRST touch, not at run start: RS
; assigned in BEGIN must govern the split, and getline in BEGIN must be
; able to read -- both fall out of laziness and neither survives an
; eager split.
(def %awk-recs-force!
  (fn (_)
    (if (eq? %awk-recs (lit unread))
      (set! %awk-recs (%awk-records %awk-input))
      ())))

; One record off the stream: the symbol eof at exhaustion -- NOT nil,
; because "" is a legitimate record (RS=";" over "a;;b" has one in the
; middle).  NR counts here; shared by the main loop and getline.
(def %awk-next-record!
  (fn (_)
    (%awk-recs-force!)
    (if (null? %awk-recs) (lit eof)
      (let ((rec (first %awk-recs)))
        (set! %awk-recs (rest %awk-recs))
        (%awk-var-set! "NR" (+ 1 (%awk-to-num (%awk-var-get "NR"))))
        rec))))

(def %awk-rule-fires?
  (fn (_ pat)
    (if (null? pat) #t
      (if (eq? (first pat) (lit ere))
        (not (null? (regex-search %awk-f0 (first (rest pat)))))
        (%awk-truthy? (%awk-eval pat))))))

(def %awk-run-rules
  (fn (self rules)
    (if (null? rules) ()
      (let ((rule (first rules)))
        (def pat (first (rest rule)))
        (def action (first (rest (rest rule))))
        (def c
          (if (%awk-rule-fires? pat)
            (if (null? action)
              (do (%awk-print! ()) ())
              (%awk-exec-list action))
            ()))
        (if (null? c) (self (rest rules))
          (if (eq? (first c) (lit next)) ()
            c))))))

(def awk-run
  (fn (_ prog input)
    (def items (awk-parse prog))
    ; reset EVERYTHING -- a raise in the previous run must not leak in
    (set! %awk-genv ())
    (set! %awk-f0 "")
    (set! %awk-fields ())
    (set! %awk-fs-cache ())
    (%awk-var-set! "FS" " ")
    (%awk-var-set! "OFS" " ")
    (%awk-var-set! "ORS" "\n")
    (%awk-var-set! "RS" "\n")
    (%awk-var-set! "NR" 0)
    (%awk-var-set! "NF" 0)
    ; SUBSEP: the multi-subscript joiner, \034 as everywhere else.
    (%awk-var-set! "SUBSEP" (list->string (list (integer->char 28))))
    (%awk-var-set! "OFMT" "%.6g")
    (%awk-var-set! "CONVFMT" "%.6g")
    (%awk-var-set! "RSTART" 0)
    (%awk-var-set! "RLENGTH" (- 0 1))
    (set! %awk-seed 0)
    (set! %awk-rng (make-rng 0))
    (set! %awk-input input)
    (set! %awk-recs (lit unread))
    (set! %awk-funcs ())
    (def begins ())
    (def ends ())
    (def rules ())
    (def sort-items
      (fn (self is)
        (unless (null? is)
          (let ((item (first is)))
            (match
              ((eq? (first item) (lit begin))
                (set! begins (append begins (first (rest item)))))
              ((eq? (first item) (lit end))
                (set! ends (append ends (first (rest item)))))
              ; functions register up front: a call may precede its
              ; definition in the program text
              ((eq? (first item) (lit func))
                (set! %awk-funcs
                  (pair
                    (pair (first (rest item))
                      (pair (first (rest (rest item)))
                        (first (rest (rest (rest item))))))
                    %awk-funcs)))
              (#t (set! rules (append rules (list item))))))
          (self (rest is)))))
    (sort-items items)
    (def c0 (%awk-exec-list begins))
    (def exited? (if (null? c0) #f (eq? (first c0) (lit exit))))
    ; Only bother with the record loop when something consumes records.
    (unless (if exited? #t (if (null? rules) (null? ends) #f))
      (let ((loop ()))
        (set! loop
          (fn (self)
            (let ((rec (%awk-next-record!)))
              (unless (eq? rec (lit eof))
                (%awk-set-record! rec)
                (let ((c (%awk-run-rules rules)))
                  (if (if (null? c) #f (eq? (first c) (lit exit)))
                    ()
                    (self)))))))
        (loop)))
    (%awk-exec-list ends)
    ()))

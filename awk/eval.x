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
      (#t (first (%awk-str-prefix-num v))))))

; --- Number formatting: %.6g from exact values -------------------------------

; trunc toward zero, via the probed fact that (% x 1) answers the
; fractional part for a non-negative rational.
(def %awk-trunc
  (fn (_ x)
    (if (< x 0) (- 0 (- (- 0 x) (% (- 0 x) 1))) (- x (% x 1)))))

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

; Fractional rendering: up to 6 decimals, round-half-up, trailing zeros
; stripped.  (%.6g additionally shifts to e-notation for very large and
; very small values; that case is a recorded pending spec, not silent.)
(def %awk-num->str
  (fn (_ n)
    (if (= 0 (% n 1))
      (%awk-int->str n)
      (let ((neg (< n 0)))
        (def a (if neg (- 0 n) n))
        (def i (%awk-trunc a))
        (def scaled (* (- a i) 1000000))
        (def d (%awk-trunc (+ scaled (/ 1 2))))
        (def i2 (if (= d 1000000) (+ i 1) i))
        (def d2 (if (= d 1000000) 0 d))
        (if (= d2 0)
          (%awk-int->str (if neg (- 0 i2) i2))
          (let ((strip ()))
            (set! strip
              (fn (self t k)
                (if (= 0 (% t 10)) (self (/ (- t (% t 10)) 10) (- k 1))
                  (pair t k))))
            (def sk (strip d2 6))
            (def digits (%awk-int->str (first sk)))
            (def pad
              (fn (self m)
                (if (<= m 0) "" (string-append "0" (self (- m 1))))))
            (string-append
              (if neg "-" "")
              (%awk-int->str i2)
              "."
              (pad (- (rest sk) (string-length digits)))
              digits)))))))

(def %awk-to-str
  (fn (_ v)
    (match
      ((null? v) "")
      ((number? v) (%awk-num->str v))
      ((%awk-strnum? v) (first (rest v)))
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

(def %awk-split-record
  (fn (_ rec)
    (def fs (%awk-to-str (%awk-var-get "FS")))
    (def texts
      (match
        ((string=? fs " ") (%awk-split-blanks rec))
        ((= (string-length fs) 1)
          (if (= (string-length rec) 0) (list "")
            (%awk-split-char rec (string-ref fs 0))))
        (#t
          (if (= (string-length rec) 0) (list "")
            (let ((rx (if (if (pair? %awk-fs-cache)
                            (string=? (first %awk-fs-cache) fs) #f)
                        (rest %awk-fs-cache)
                        (let ((c (regex-compile fs)))
                          (set! %awk-fs-cache (pair fs c))
                          c))))
              (regex-split rec rx))))))
    (map (fn (_ t) (%awk-input-val t)) texts)))

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

(def %awk-builtin
  (fn (_ name args)
    (match
      ((string=? name "length")
        (string-length
          (if (null? args) %awk-f0 (%awk-to-str (first args)))))
      ((string=? name "index")
        (%awk-str-index (%awk-to-str (first args))
          (%awk-to-str (first (rest args)))))
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

(def %awk-lval-get
  (fn (_ lv)
    (if (eq? (first lv) (lit var))
      (%awk-var-get (first (rest lv)))
      (%awk-field-get (%awk-to-num (%awk-eval (first (rest lv))))))))

(def %awk-lval-set!
  (fn (_ lv v)
    (if (eq? (first lv) (lit var))
      (%awk-var-set! (first (rest lv)) v)
      (Err raise (lit awk) "awk: assigning to a field is not built yet" lv))))

(def %awk-incr!
  (fn (_ lv delta pre?)
    (def old (%awk-to-num (%awk-lval-get lv)))
    (def new (+ old delta))
    (%awk-lval-set! lv new)
    (if pre? new old)))

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
      ((eq? tag (lit assign))
        (let ((v (%awk-eval (first (rest (rest node))))))
          (%awk-lval-set! (first (rest node)) v)
          v))
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
      ((eq? tag (lit preinc)) (%awk-incr! (first (rest node)) 1 #t))
      ((eq? tag (lit postinc)) (%awk-incr! (first (rest node)) 1 #f))
      ((eq? tag (lit predec)) (%awk-incr! (first (rest node)) (- 0 1) #t))
      ((eq? tag (lit postdec)) (%awk-incr! (first (rest node)) (- 0 1) #f))
      ((eq? tag (lit call))
        (%awk-builtin (first (rest node))
          (map (fn (_ a) (%awk-eval a)) (first (rest (rest node))))))
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

(def %awk-print!
  (fn (_ args)
    (def ofs (%awk-to-str (%awk-var-get "OFS")))
    (def go
      (fn (self as first?)
        (unless (null? as)
          (unless first? (display ofs))
          (display (%awk-to-str (%awk-eval (first as))))
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
      ((eq? tag (lit next)) (list (lit next)))
      ((eq? tag (lit break)) (list (lit break)))
      ((eq? tag (lit continue)) (list (lit continue)))
      ((eq? tag (lit exit))
        (list (lit exit)
          (if (null? (first (rest stmt))) 0
            (%awk-to-num (%awk-eval (first (rest stmt)))))))
      (#t (Err raise (lit awk) "awk: unknown statement" tag)))))

; --- The record loop ---------------------------------------------------------

; Records: input split on newline; a trailing newline closes the last
; record rather than opening an empty one.
(def %awk-records
  (fn (_ input)
    (def all (%awk-split-char input #\newline))
    (def drop-last
      (fn (self l)
        (if (null? (rest l)) () (pair (first l) (self (rest l))))))
    (if (null? all) ()
      (if (= (string-length input) 0) ()
        (if (= (string-ref input (- (string-length input) 1)) #\newline)
          (drop-last all)
          all)))))

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
    (%awk-var-set! "NR" 0)
    (%awk-var-set! "NF" 0)
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
              (#t (set! rules (append rules (list item))))))
          (self (rest is)))))
    (sort-items items)
    (def c0 (%awk-exec-list begins))
    (def exited? (if (null? c0) #f (eq? (first c0) (lit exit))))
    ; Only bother with the record loop when something consumes records.
    (unless (if exited? #t (if (null? rules) (null? ends) #f))
      (let ((loop ()))
        (set! loop
          (fn (self recs)
            (unless (null? recs)
              (%awk-var-set! "NR" (+ 1 (%awk-to-num (%awk-var-get "NR"))))
              (%awk-set-record! (first recs))
              (let ((c (%awk-run-rules rules)))
                (if (if (null? c) #f (eq? (first c) (lit exit)))
                  ()
                  (self (rest recs)))))))
        (loop (%awk-records input))))
    (%awk-exec-list ends)
    ()))

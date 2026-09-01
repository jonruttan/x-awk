; # x-awk -- POSIX awk on x-lang
;
; ## awk/lex.x -- program text to tokens
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A STRING SCANNER, the lib/x/type/regex.x shape: an index walked down the
; source with string-ref, tokens consed in reverse and flipped once.  No
; reader base -- see awk/base.x for why.
;
; TOKENS (what the parser sees, and what the lexer specs assert):
;   (num N)      numeric constant, already a NUMBER (exact -- see eval.x)
;   (str "s")    string constant, escapes processed
;   (ere "pat")  /pattern/ text, compiled at PARSE time
;   (name "x")   identifier
;   (kw SYM)     keyword: BEGIN END if else while for do print next
;   (op "s")     operator or punctuation, multi-char folded: == <= && ++ ...
;   (nl)         newline -- a statement terminator, runs collapsed to one
;
; THE / AMBIGUITY is awk's one lexing subtlety: `a/b` divides, `/re/`
; matches.  POSIX resolves it by context and so does this lexer: a `/` is
; division only when the PREVIOUS token could end an expression -- a
; constant, a name, `)` or `]`, or the ERE it would close -- and starts a
; regex everywhere else.  One boolean threaded down the scan carries it.

; --- Character predicates (codes, not chars: one cast per character) ---------

(def %awk-lex-digit? (fn (_ ci) (if (>= ci 48) (<= ci 57) #f)))
(def %awk-lex-name-start?
  (fn (_ ci)
    (if (if (>= ci 65) (<= ci 90) #f) #t
      (if (if (>= ci 97) (<= ci 122) #f) #t
        (= ci 95)))))
(def %awk-lex-name-char?
  (fn (_ ci) (if (%awk-lex-name-start? ci) #t (%awk-lex-digit? ci))))

; --- Keywords ----------------------------------------------------------------

(def %awk-keywords
  (list "BEGIN" "END" "function" "if" "else" "while" "for" "do"
        "break" "continue" "next" "exit" "return" "delete" "in"
        "print" "printf" "getline"))

(def %awk-kw?
  (fn (_ s)
    (def go
      (fn (self ks)
        (if (null? ks) #f
          (if (string=? s (first ks)) #t (self (rest ks))))))
    (go %awk-keywords)))

; --- Sub-scanners ------------------------------------------------------------
; Each answers (token . next-index); the driver conses and continues.

; 10^k as an exact integer, for the mantissa/exponent assembly.
(def %awk-pow10
  (fn (self k) (if (<= k 0) 1 (* 10 (self (- k 1))))))

; Number: digits [. digits] [(e|E) [+|-] digits].  Assembled EXACTLY:
; 1.5 becomes 3/2, 25e-2 becomes 1/4.  eval.x owns turning these back
; into awk-formatted text.
(def %awk-lex-num
  (fn (_ src i end)
    (def int-part
      (fn (self j acc)
        (if (>= j end) (pair acc j)
          (let ((ci (char->integer (string-ref src j))))
            (if (%awk-lex-digit? ci)
              (self (+ j 1) (+ (* acc 10) (- ci 48)))
              (pair acc j))))))
    (def ir (int-part i 0))
    (def ival (first ir))
    (def after-int (rest ir))
    ; fractional digits, tracked as (value . count)
    (def frac-part
      (fn (self j acc k)
        (if (>= j end) (pair (pair acc k) j)
          (let ((ci (char->integer (string-ref src j))))
            (if (%awk-lex-digit? ci)
              (self (+ j 1) (+ (* acc 10) (- ci 48)) (+ k 1))
              (pair (pair acc k) j))))))
    (def fr
      (if (if (< after-int end) (= (string-ref src after-int) #\.) #f)
        (frac-part (+ after-int 1) 0 0)
        (pair (pair 0 0) after-int)))
    (def fval (first (first fr)))
    (def fcount (rest (first fr)))
    (def after-frac (rest fr))
    (def mant (+ ival (/ fval (%awk-pow10 fcount))))
    ; exponent: e/E, only when digits actually follow (else `1e` is a
    ; number then a name, awk's own reading)
    (def exp-part
      (fn (_ j)
        (if (>= j end) ()
          (let ((c (string-ref src j)))
            (if (if (= c #\e) #t (= c #\E))
              (let ((k (+ j 1)))
                (def neg (if (< k end) (= (string-ref src k) #\-) #f))
                (def k2 (if (if (< k end)
                              (if (= (string-ref src k) #\+) #t
                                (= (string-ref src k) #\-)) #f)
                          (+ k 1) k))
                (if (if (< k2 end)
                      (%awk-lex-digit? (char->integer (string-ref src k2))) #f)
                  (let ((er (int-part k2 0)))
                    (pair (if neg (- 0 (first er)) (first er)) (rest er)))
                  ()))
              ())))))
    (def er (exp-part after-frac))
    (if (null? er)
      (pair (list (lit num) mant) after-frac)
      (let ((e (first er)))
        (pair
          (list (lit num)
            (if (< e 0) (/ mant (%awk-pow10 (- 0 e))) (* mant (%awk-pow10 e))))
          (rest er))))))

; String constant: escapes processed here, so the parser and evaluator only
; ever see the text meant.  Chars accumulate reversed; one list->string.
(def %awk-lex-str
  (fn (_ src i end)
    (def go
      (fn (self j acc)
        (if (>= j end)
          (pair (list (lit str) (list->string (reverse acc))) j)
          (let ((c (string-ref src j)))
            (match
              ((= c #\")
                (pair (list (lit str) (list->string (reverse acc))) (+ j 1)))
              ((= c #\\)
                (if (>= (+ j 1) end) (self (+ j 1) (pair c acc))
                  (let ((e (string-ref src (+ j 1))))
                    (match
                      ((= e #\n) (self (+ j 2) (pair (integer->char 10) acc)))
                      ((= e #\t) (self (+ j 2) (pair (integer->char 9) acc)))
                      ((= e #\r) (self (+ j 2) (pair (integer->char 13) acc)))
                      ((= e #\\) (self (+ j 2) (pair #\\ acc)))
                      ((= e #\") (self (+ j 2) (pair #\" acc)))
                      ((= e #\/) (self (+ j 2) (pair #\/ acc)))
                      (#t (self (+ j 2) (pair e acc)))))))
              (#t (self (+ j 1) (pair c acc))))))))
    (go i ())))

; ERE literal: everything to the unescaped closing /.  Only \/ is handled
; here (it means a literal / INSIDE the pattern); every other backslash
; passes through untouched for the regex compiler to read.
(def %awk-lex-ere
  (fn (_ src i end)
    (def go
      (fn (self j acc)
        (if (>= j end)
          (pair (list (lit ere) (list->string (reverse acc))) j)
          (let ((c (string-ref src j)))
            (match
              ((= c #\/)
                (pair (list (lit ere) (list->string (reverse acc))) (+ j 1)))
              ((= c #\\)
                (if (>= (+ j 1) end) (self (+ j 1) (pair c acc))
                  (let ((e (string-ref src (+ j 1))))
                    (if (= e #\/)
                      (self (+ j 2) (pair #\/ acc))
                      (self (+ j 2) (pair e (pair c acc)))))))
              (#t (self (+ j 1) (pair c acc))))))))
    (go i ())))

; Name, keyword, or -- when a ( follows with NO space between -- a
; function name.  That adjacency is POSIX's own FUNC_NAME rule, and it is
; what disambiguates `f(1)` (a call) from `f (1)` (concatenation of f and
; a parenthesized 1).  The parser routes a funcname to a builtin or a
; user call; the lexer only records the shape.
(def %awk-lex-name
  (fn (_ src i end)
    (def go
      (fn (self j acc)
        (if (>= j end) (pair (list->string (reverse acc)) j)
          (let ((ci (char->integer (string-ref src j))))
            (if (%awk-lex-name-char? ci)
              (self (+ j 1) (pair (string-ref src j) acc))
              (pair (list->string (reverse acc)) j))))))
    (def r (go i ()))
    (def s (first r))
    (def j (rest r))
    (pair
      (match
        ((%awk-kw? s) (list (lit kw) (convert s %symbol)))
        ((if (< j end) (= (string-ref src j) #\() #f)
          (list (lit funcname) s))
        (#t (list (lit name) s)))
      j)))

; Operator: longest match first.  The two-char set, then the singles.
(def %awk-lex2
  (list "==" "!=" "<=" ">=" "&&" "||" "++" "--"
        "+=" "-=" "*=" "/=" "%=" "^=" "!~" ">>"))

(def %awk-lex-op
  (fn (_ src i end)
    (def two
      (if (< (+ i 1) end)
        (substring src i (+ i 2))
        ()))
    (def hit2
      (fn (self ks)
        (if (null? ks) ()
          (if (string=? two (first ks)) (first ks) (self (rest ks))))))
    (def m2 (if (null? two) () (hit2 %awk-lex2)))
    (if (not (null? m2))
      (pair (list (lit op) m2) (+ i 2))
      (pair (list (lit op) (substring src i (+ i 1))) (+ i 1)))))

; --- The driver --------------------------------------------------------------
; div-ok: could the previous token END an expression?  (See header.)

(def %awk-lex-div-after?
  (fn (_ tok)
    (def tag (first tok))
    (match
      ((eq? tag (lit num)) #t)
      ((eq? tag (lit str)) #t)
      ((eq? tag (lit ere)) #t)
      ((eq? tag (lit name)) #t)
      ((eq? tag (lit op))
        (let ((s (first (rest tok))))
          (if (string=? s ")") #t
            (if (string=? s "]") #t
              (if (string=? s "++") #t (string=? s "--"))))))
      (#t #f))))

(def awk-tokenize
  (fn (_ src)
    (def end (string-length src))
    (def go
      (fn (self i div-ok acc)
        (if (>= i end) (reverse acc)
          (let ((c (string-ref src i)))
            (def ci (char->integer c))
            (match
              ; space and tab: skip
              ((if (= ci 32) #t (= ci 9)) (self (+ i 1) div-ok acc))
              ; backslash-newline: line continuation, skip both
              ((if (= c #\\)
                 (if (< (+ i 1) end) (= (string-ref src (+ i 1)) #\newline) #f)
                 #f)
                (self (+ i 2) div-ok acc))
              ; newline: one (nl), runs collapsed
              ((= ci 10)
                (if (if (pair? acc) (eq? (first (first acc)) (lit nl)) #f)
                  (self (+ i 1) #f acc)
                  (self (+ i 1) #f (pair (list (lit nl)) acc))))
              ; comment to end of line
              ((= c #\#)
                (let ((skip (fn (self2 j)
                              (if (>= j end) j
                                (if (= (string-ref src j) #\newline) j
                                  (self2 (+ j 1)))))))
                  (self (skip (+ i 1)) div-ok acc)))
              ; string constant
              ((= c #\")
                (let ((r (%awk-lex-str src (+ i 1) end)))
                  (self (rest r) #t (pair (first r) acc))))
              ; slash: divide or ERE, by context
              ((= c #\/)
                (if div-ok
                  (let ((r (%awk-lex-op src i end)))
                    (self (rest r) #f (pair (first r) acc)))
                  (let ((r (%awk-lex-ere src (+ i 1) end)))
                    (self (rest r) #t (pair (first r) acc)))))
              ; number: digit, or . with a digit after it
              ((%awk-lex-digit? ci)
                (let ((r (%awk-lex-num src i end)))
                  (self (rest r) #t (pair (first r) acc))))
              ((if (= c #\.)
                 (if (< (+ i 1) end)
                   (%awk-lex-digit? (char->integer (string-ref src (+ i 1))))
                   #f)
                 #f)
                (let ((r (%awk-lex-num src i end)))
                  (self (rest r) #t (pair (first r) acc))))
              ; name or keyword
              ((%awk-lex-name-start? ci)
                (let ((r (%awk-lex-name src i end)))
                  (self (rest r) (%awk-lex-div-after? (first r))
                    (pair (first r) acc))))
              ; operator or punctuation
              (#t
                (let ((r (%awk-lex-op src i end)))
                  (self (rest r) (%awk-lex-div-after? (first r))
                    (pair (first r) acc)))))))))
    (go 0 #f ())))

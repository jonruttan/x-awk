; # x-awk -- POSIX awk on x-lang
;
; ## awk/fmt.x -- the printf format engine
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; %awk-sprintf FMT VALS -> string.  Serves printf, sprintf, and -- through
; OFMT/CONVFMT -- every number-to-string conversion in the bundle, so the
; one engine owns all rendering.  Conversions: d i o x X u c s f e E g G %%
; with the flags - + space 0 #, width, precision, and * for either.
;
; EXACT ALL THE WAY DOWN: the value arrives rational, and every digit here
; comes from integer arithmetic on it -- no doubles anywhere.  Rounding is
; HALF-UP; C's doubles round half-EVEN, so %.0f of 2.5 answers 3 here and
; 2 there -- a recorded pending divergence, not a surprise.  Negative
; values under x/X/o/u render sign-prefixed rather than wrapping to
; unsigned long, same status.
;
; Not enough arguments is a RAISE: the one-true-awk errors here too, and
; a silently-substituted zero is the crafting doc's silent wrong number.

; n >= 0 integer to digits in base (2..16).
(def %awk-fmt-digits
  (fn (_ n base upper)
    (if (= n 0) "0"
      (let ((go ()))
        (set! go
          (fn (self t acc)
            (if (= t 0) acc
              (let ((d (% t base)))
                (self (/ (- t d) base)
                  (pair (integer->char
                          (if (< d 10) (+ 48 d)
                            (+ (if upper 55 87) d)))
                    acc))))))
        (list->string (go n ()))))))

(def %awk-fmt-zeros
  (fn (self k) (if (<= k 0) "" (string-append "0" (self (- k 1))))))

(def %awk-fmt-spaces
  (fn (self k) (if (<= k 0) "" (string-append " " (self (- k 1))))))

; Left-pad digits with zeros to at least k characters.
(def %awk-fmt-zpad
  (fn (_ s k) (string-append (%awk-fmt-zeros (- k (string-length s))) s)))

; Strip trailing zeros from a fraction-digit string (%g's tidy-up).
(def %awk-fmt-strip
  (fn (_ s)
    (def go
      (fn (self i)
        (if (<= i 0) 0
          (if (= (string-ref s (- i 1)) #\0) (self (- i 1)) i))))
    (substring s 0 (go (string-length s)))))

; Fixed-point body for a >= 0: DECS digits after the point, half-up,
; trailing zeros stripped when STRIP.
(def %awk-fmt-fixed
  (fn (_ a decs strip)
    (def i (%awk-trunc a))
    (def scale (%awk-pow10 decs))
    (def d (%awk-trunc (+ (* (- a i) scale) (/ 1 2))))
    (def i2 (if (= d scale) (+ i 1) i))
    (def d2 (if (= d scale) 0 d))
    (def frac
      (if (= decs 0) ""
        (let ((digits (%awk-fmt-zpad (%awk-fmt-digits d2 10 #f) decs)))
          (if strip (%awk-fmt-strip digits) digits))))
    (if (= (string-length frac) 0)
      (%awk-fmt-digits (%awk-trunc i2) 10 #f)
      (string-append (%awk-fmt-digits (%awk-trunc i2) 10 #f)
        (string-append "." frac)))))

; Normalize a > 0 to mant in [1,10): (mant . exponent).
(def %awk-fmt-norm
  (fn (_ a)
    (def up
      (fn (self m e) (if (< m 1) (self (* m 10) (- e 1)) (pair m e))))
    (def down
      (fn (self m e) (if (>= m 10) (self (/ m 10) (+ e 1)) (pair m e))))
    (if (< a 1) (up a 0) (down a 0))))

; Scientific body for a >= 0: mantissa to DECS decimals, e[+-]NN with the
; exponent at least two digits.
(def %awk-fmt-sci
  (fn (_ a decs strip upper)
    (def norm (if (= a 0) (pair 0 0) (%awk-fmt-norm a)))
    (def m (first norm))
    (def e (rest norm))
    ; round the mantissa; a carry to 10.0 renormalizes
    (def scale (%awk-pow10 decs))
    (def md (%awk-trunc (+ (* m scale) (/ 1 2))))
    (def carried (>= md (* 10 scale)))
    (def md2 (if carried (/ md 10) md))
    (def e2 (if (if carried (not (= a 0)) #f) (+ e 1) e))
    (def md3 (%awk-trunc md2))
    (def all (%awk-fmt-zpad (%awk-fmt-digits md3 10 #f) (+ decs 1)))
    (def head (substring all 0 1))
    (def frac
      (if (= decs 0) ""
        (let ((digits (substring all 1 (string-length all))))
          (if strip (%awk-fmt-strip digits) digits))))
    (string-append
      (if (= (string-length frac) 0) head
        (string-append head (string-append "." frac)))
      (string-append
        (if upper "E" "e")
        (string-append
          (if (< e2 0) "-" "+")
          (%awk-fmt-zpad (%awk-fmt-digits (if (< e2 0) (- 0 e2) e2) 10 #f)
            2))))))

; %g body for a >= 0: %e when the exponent leaves [-4, prec), %f inside,
; either way with trailing zeros stripped (prec 0 reads as 1).
(def %awk-fmt-g
  (fn (_ a prec upper)
    (def p (if (< prec 1) 1 prec))
    (if (= a 0) "0"
      (let ((e (rest (%awk-fmt-norm a))))
        (if (if (< e (- 0 4)) #t (>= e p))
          (%awk-fmt-sci a (- p 1) #t upper)
          (%awk-fmt-fixed a (- p 1 e) #t))))))

; Apply flags and width to a numeric (sign . body) or a plain string.
; Zero-padding slots between the sign and the body; left-justify wins
; over zero.
(def %awk-fmt-pad-num
  (fn (_ sign body width left zero)
    (def bare (string-append sign body))
    (def gap (- width (string-length bare)))
    (match
      ((<= gap 0) bare)
      (left (string-append bare (%awk-fmt-spaces gap)))
      (zero (string-append sign (string-append (%awk-fmt-zeros gap) body)))
      (#t (string-append (%awk-fmt-spaces gap) bare)))))

(def %awk-fmt-pad-str
  (fn (_ s width left)
    (def gap (- width (string-length s)))
    (if (<= gap 0) s
      (if left
        (string-append s (%awk-fmt-spaces gap))
        (string-append (%awk-fmt-spaces gap) s)))))

; The sign prefix a numeric conversion owes: - always, else + or space
; when their flags ask.
(def %awk-fmt-sign
  (fn (_ neg plus space)
    (if neg "-" (if plus "+" (if space " " "")))))

; --- The scanner -------------------------------------------------------------

(def %awk-sprintf ())

; One conversion, spec already parsed.  Answers the rendered piece.
(def %awk-fmt-one
  (fn (_ conv v flag-minus flag-plus flag-space flag-zero flag-alt width prec)
    (match
      ((= conv #\%) (%awk-fmt-pad-str "%" width flag-minus))
      ((if (= conv #\d) #t (if (= conv #\i) #t (= conv #\u)))
        (let ((n (%awk-trunc (%awk-to-num v))))
          (def neg (< n 0))
          (def body (%awk-fmt-digits (if neg (- 0 n) n) 10 #f))
          (def body2 (if (< prec 0) body (%awk-fmt-zpad body prec)))
          (%awk-fmt-pad-num (%awk-fmt-sign neg flag-plus flag-space) body2
            width flag-minus (if (< prec 0) flag-zero #f))))
      ((if (= conv #\x) #t (if (= conv #\X) #t (= conv #\o)))
        (let ((n (%awk-trunc (%awk-to-num v))))
          (def neg (< n 0))
          (def base (if (= conv #\o) 8 16))
          (def body (%awk-fmt-digits (if neg (- 0 n) n) base (= conv #\X)))
          (def body2 (if (< prec 0) body (%awk-fmt-zpad body prec)))
          (def body3
            (match
              ((not flag-alt) body2)
              ((= conv #\o)
                (if (= (string-ref body2 0) #\0) body2
                  (string-append "0" body2)))
              ((= n 0) body2)
              (#t (string-append (if (= conv #\X) "0X" "0x") body2))))
          (%awk-fmt-pad-num (if neg "-" "") body3
            width flag-minus (if (< prec 0) flag-zero #f))))
      ((= conv #\c)
        (let ((s (if (number? v)
                   (list->string (list (integer->char (%awk-trunc v))))
                   (let ((t (%awk-to-str v)))
                     (if (= (string-length t) 0) "" (substring t 0 1))))))
          (%awk-fmt-pad-str s width flag-minus)))
      ((= conv #\s)
        (let ((s (%awk-to-str v)))
          (def s2 (if (if (>= prec 0) (> (string-length s) prec) #f)
                    (substring s 0 prec) s))
          (%awk-fmt-pad-str s2 width flag-minus)))
      ((= conv #\f)
        (let ((n (%awk-to-num v)))
          (def neg (< n 0))
          (%awk-fmt-pad-num (%awk-fmt-sign neg flag-plus flag-space)
            (%awk-fmt-fixed (if neg (- 0 n) n) (if (< prec 0) 6 prec) #f)
            width flag-minus flag-zero)))
      ((if (= conv #\e) #t (= conv #\E))
        (let ((n (%awk-to-num v)))
          (def neg (< n 0))
          (%awk-fmt-pad-num (%awk-fmt-sign neg flag-plus flag-space)
            (%awk-fmt-sci (if neg (- 0 n) n) (if (< prec 0) 6 prec) #f
              (= conv #\E))
            width flag-minus flag-zero)))
      ((if (= conv #\g) #t (= conv #\G))
        (let ((n (%awk-to-num v)))
          (def neg (< n 0))
          (%awk-fmt-pad-num (%awk-fmt-sign neg flag-plus flag-space)
            (%awk-fmt-g (if neg (- 0 n) n) (if (< prec 0) 6 prec)
              (= conv #\G))
            width flag-minus flag-zero)))
      (#t (Err raise (lit awk)
            "awk: printf: unknown conversion character" conv)))))

(set! %awk-sprintf
  (fn (_ fmt vals)
    (def end (string-length fmt))
    (def take
      (fn (_ vs)
        (if (null? vs)
          (Err raise (lit awk) "awk: printf: not enough arguments" fmt)
          (pair (first vs) (rest vs)))))
    ; parse [flags][width][.prec]CONV from position i; %% consumes no value
    (def conv
      (fn (_ i vs)
        ; flags
        (def flags
          (fn (self j m p s z a)
            (if (>= j end) (list j m p s z a)
              (let ((ci (char->integer (string-ref fmt j))))
                (match
                  ((= ci 45) (self (+ j 1) #t p s z a))    ; -
                  ((= ci 43) (self (+ j 1) m #t s z a))    ; +
                  ((= ci 32) (self (+ j 1) m p #t z a))    ; space
                  ((= ci 48) (self (+ j 1) m p s #t a))    ; 0
                  ((= ci 35) (self (+ j 1) m p s z #t))    ; #
                  (#t (list j m p s z a)))))))
        (def f (flags i #f #f #f #f #f))
        (def j0 (first f))
        (def minus (first (rest f)))
        (def plus (first (rest (rest f))))
        (def space (first (rest (rest (rest f)))))
        (def zero (first (rest (rest (rest (rest f))))))
        (def alt (first (rest (rest (rest (rest (rest f)))))))
        ; a number in the spec: (value . next-index)
        (def num
          (fn (self j acc)
            (if (>= j end) (pair acc j)
              (let ((ci (char->integer (string-ref fmt j))))
                (if (%awk-lex-digit? ci)
                  (self (+ j 1) (+ (* acc 10) (- ci 48)))
                  (pair acc j))))))
        ; width: * pulls a value (negative reads as left-justified |w|)
        (def wr
          (if (if (< j0 end) (= (string-ref fmt j0) #\*) #f)
            (let ((t (take vs)))
              (list (%awk-trunc (%awk-to-num (first t))) (+ j0 1) (rest t)))
            (let ((r (num j0 0))) (list (first r) (rest r) vs))))
        (def w0 (first wr))
        (def j1 (first (rest wr)))
        (def vs1 (first (rest (rest wr))))
        (def minus2 (if (< w0 0) #t minus))
        (def w (if (< w0 0) (- 0 w0) w0))
        ; precision: absent -> -1
        (def pr
          (if (if (< j1 end) (= (string-ref fmt j1) #\.) #f)
            (if (if (< (+ j1 1) end) (= (string-ref fmt (+ j1 1)) #\*) #f)
              (let ((t (take vs1)))
                (list (%awk-trunc (%awk-to-num (first t))) (+ j1 2) (rest t)))
              (let ((r (num (+ j1 1) 0))) (list (first r) (rest r) vs1)))
            (list (- 0 1) j1 vs1)))
        (def p (first pr))
        (def j2 (first (rest pr)))
        (def vs2 (first (rest (rest pr))))
        (if (>= j2 end)
          (Err raise (lit awk) "awk: printf: format ends inside a % spec" fmt)
          (let ((c (string-ref fmt j2)))
            (if (= c #\%)
              (list (%awk-fmt-one c () minus2 plus space zero alt w p)
                (+ j2 1) vs2)
              (let ((t (take vs2)))
                (list
                  (%awk-fmt-one c (first t) minus2 plus space zero alt w p)
                  (+ j2 1) (rest t))))))))
    (def go
      (fn (self i vs pieces)
        (if (>= i end)
          (string-concat (reverse pieces))
          (let ((c (string-ref fmt i)))
            (if (= c #\%)
              (if (>= (+ i 1) end)
                (self (+ i 1) vs (pair "%" pieces))
                (let ((r (conv (+ i 1) vs)))
                  (self (first (rest r)) (first (rest (rest r)))
                    (pair (first r) pieces))))
              (self (+ i 1) vs (pair (substring fmt i (+ i 1)) pieces)))))))
    (go 0 vals ())))

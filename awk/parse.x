; # x-awk -- POSIX awk on x-lang
;
; ## awk/parse.x -- tokens to a program
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; GRAMMAR ONLY (crafting-a-lang.md section 3): this file knows tokens and
; AST shapes, never what an operator means.  Every function is PURE and
; answers (ast . remaining-tokens) -- the lib/x/type/regex.x threading, so
; lookahead is free: peek by parsing ahead and discarding.
;
; THE AST (what the parser specs assert):
;   items:  (begin STMTS) (end STMTS) (rule PAT ACTION)
;           PAT () = every record; ACTION () = print $0
;   stmts:  (print ARGS) (printf ARGS) (if C T E) (while C B) (do B C)
;           (for I C U B)
;           (for-in VAR ARRAY B) (delete NAME SUBS|())
;           (block STMTS) (expr E) (next) (break) (continue) (exit E|())
;   exprs:  (num N) (str S) (ere RX) (var NAME) (field E)
;           (index NAME SUBS) (in KEY ARRAYNAME)
;           (assign LV E) (ternary C A B) (or A B) (and A B)
;           (match A B) (nomatch A B) (cmp "op" A B) (concat A B)
;           (bin "op" A B) (neg E) (not E) (pow A B)
;           (preinc LV) (postinc LV) (predec LV) (postdec LV)
;           (call NAME ARGS)
;
; EREs COMPILE HERE, once: the lexer hands pattern TEXT, the AST carries the
; compiled regex.  A pattern that does not compile fails at parse time with
; the program position still known, not at the first record.
;
; PRINT FORBIDS BARE `>` (gt=#f threads down the ladder): in awk,
; `print a > b` REDIRECTS, and redirection is not built yet.  Refusing the
; token is louder than silently comparing -- the crafting doc's rule that a
; loud error beats a silent wrong number.  Parenthesized comparison
; (`print (a > b)`) parses fine.

; --- Token peeks -------------------------------------------------------------

(def %awk-p-tag
  (fn (_ toks) (if (null? toks) (lit eof) (first (first toks)))))

(def %awk-p-op?
  (fn (_ toks s)
    (if (null? toks) #f
      (if (eq? (first (first toks)) (lit op))
        (string=? (first (rest (first toks))) s)
        #f))))

(def %awk-p-kw?
  (fn (_ toks k)
    (if (null? toks) #f
      (if (eq? (first (first toks)) (lit kw))
        (eq? (first (rest (first toks))) k)
        #f))))

(def %awk-p-skip-nl
  (fn (self toks)
    (if (if (pair? toks) (eq? (first (first toks)) (lit nl)) #f)
      (self (rest toks))
      toks)))

; A statement boundary: newline, semicolon, closing brace, or the end.
(def %awk-p-term?
  (fn (_ toks)
    (if (null? toks) #t
      (if (eq? (%awk-p-tag toks) (lit nl)) #t
        (if (%awk-p-op? toks ";") #t (%awk-p-op? toks "}"))))))

(def %awk-p-err
  (fn (_ msg toks)
    (Err raise (lit awk)
      (string-append "awk parse: " msg
        (if (null? toks) " at end of program" " near a token"))
      toks)))

; The expression ladder, forward-declared for the mutual recursion.
(def %awk-p-expr ())        ; ternary and below; (toks gt) -> (ast . rest)
(def %awk-p-stmt ())
(def %awk-p-stmts ())

; --- Primary -----------------------------------------------------------------

; l-value or not: assignment and ++/-- land on (var _), (field _), or an
; array element (index _ _).
(def %awk-p-lval?
  (fn (_ ast)
    (if (eq? (first ast) (lit var)) #t
      (if (eq? (first ast) (lit field)) #t
        (eq? (first ast) (lit index))))))

; The builtins the parser recognises as calls.  `length` alone (no parens)
; is also legal awk and handled in primary.
(def %awk-p-builtins
  (list "length" "substr" "index" "int" "split" "sprintf" "sub" "gsub"
        "match" "toupper" "tolower" "sin" "cos" "atan2" "exp" "log" "sqrt"
        "rand" "srand"))

(def %awk-p-builtin?
  (fn (_ s)
    (def go
      (fn (self ks)
        (if (null? ks) #f
          (if (string=? s (first ks)) #t (self (rest ks))))))
    (go %awk-p-builtins)))

; Comma-separated argument list after an opening paren; ) consumed.
(def %awk-p-args
  (fn (_ toks)
    (if (%awk-p-op? toks ")")
      (pair () (rest toks))
      (let ((loop ()))
        (set! loop
          (fn (self ts acc)
            (def r (%awk-p-expr ts #t))
            (def ts2 (rest r))
            (if (%awk-p-op? ts2 ",")
              (self (%awk-p-skip-nl (rest ts2)) (pair (first r) acc))
              (if (%awk-p-op? ts2 ")")
                (pair (reverse (pair (first r) acc)) (rest ts2))
                (%awk-p-err "expected , or ) in argument list" ts2)))))
        (loop toks ())))))

; Subscript list: a[e] or a[e1, e2, ...]; ] consumed.  Multiple
; subscripts join with SUBSEP at eval time -- POSIX's one-key reading.
(def %awk-p-subs
  (fn (_ toks)
    (def loop ())
    (set! loop
      (fn (self ts acc)
        (def r (%awk-p-expr ts #t))
        (def ts2 (rest r))
        (if (%awk-p-op? ts2 ",")
          (self (%awk-p-skip-nl (rest ts2)) (pair (first r) acc))
          (if (%awk-p-op? ts2 "]")
            (pair (reverse (pair (first r) acc)) (rest ts2))
            (%awk-p-err "expected , or ] in subscript" ts2)))))
    (loop toks ())))

(def %awk-p-primary
  (fn (_ toks gt)
    (if (null? toks) (%awk-p-err "expected an expression" toks)
      (let ((tok (first toks)))
        (def tag (first tok))
        (match
          ((eq? tag (lit num)) (pair tok (rest toks)))
          ((eq? tag (lit str)) (pair tok (rest toks)))
          ((eq? tag (lit ere))
            (pair (list (lit ere) (regex-compile (first (rest tok))))
              (rest toks)))
          ; funcname: the lexer saw `name(` with no space -- a builtin
          ; call or a user call, by the name.
          ((eq? tag (lit funcname))
            (let ((nm (first (rest tok))))
              (let ((r (%awk-p-args (rest (rest toks)))))
                (pair
                  (if (%awk-p-builtin? nm)
                    (list (lit call) nm (first r))
                    (list (lit ucall) nm (first r)))
                  (rest r)))))
          ((eq? tag (lit name))
            (let ((nm (first (rest tok))))
              (match
                ; a builtin tolerates space before its ( -- POSIX gives
                ; BUILTIN_FUNC_NAME no adjacency rule
                ((if (%awk-p-builtin? nm) (%awk-p-op? (rest toks) "(") #f)
                  (let ((r (%awk-p-args (rest (rest toks)))))
                    (pair (list (lit call) nm (first r)) (rest r))))
                ((%awk-p-op? (rest toks) "[")
                  (let ((r (%awk-p-subs (rest (rest toks)))))
                    (pair (list (lit index) nm (first r)) (rest r))))
                ((string=? nm "length")
                  (pair (list (lit call) "length" ()) (rest toks)))
                (#t (pair (list (lit var) nm) (rest toks))))))
          ; getline [var]: the main-input forms; file and pipe forms
          ; arrive with the CLI front.
          ((%awk-p-kw? toks (lit getline))
            (if (eq? (%awk-p-tag (rest toks)) (lit name))
              (pair
                (list (lit getline)
                  (list (lit var) (first (rest (first (rest toks))))))
                (rest (rest toks)))
              (pair (list (lit getline) ()) (rest toks))))
          ((%awk-p-op? toks "(")
            (let ((r (%awk-p-expr (%awk-p-skip-nl (rest toks)) #t)))
              (if (%awk-p-op? (rest r) ")")
                (pair (first r) (rest (rest r)))
                (%awk-p-err "expected )" (rest r)))))
          ((%awk-p-op? toks "$")
            ; $ binds tighter than everything: $i++ increments the FIELD
            ; ref's value, $a b concatenates $a with b.  The index is a
            ; primary, so $NF+1 is ($NF)+1, awk's own reading.
            (let ((r (%awk-p-primary (rest toks) gt)))
              (pair (list (lit field) (first r)) (rest r))))
          ((%awk-p-op? toks "!")
            (let ((r (%awk-p-primary (rest toks) gt)))
              (pair (list (lit not) (first r)) (rest r))))
          ((%awk-p-op? toks "-")
            (let ((r (%awk-p-primary (rest toks) gt)))
              (pair (list (lit neg) (first r)) (rest r))))
          ((%awk-p-op? toks "+")
            (let ((r (%awk-p-primary (rest toks) gt)))
              (pair (first r) (rest r))))
          ((%awk-p-op? toks "++")
            (let ((r (%awk-p-primary (rest toks) gt)))
              (if (%awk-p-lval? (first r))
                (pair (list (lit preinc) (first r)) (rest r))
                (%awk-p-err "++ needs a variable or field" toks))))
          ((%awk-p-op? toks "--")
            (let ((r (%awk-p-primary (rest toks) gt)))
              (if (%awk-p-lval? (first r))
                (pair (list (lit predec) (first r)) (rest r))
                (%awk-p-err "-- needs a variable or field" toks))))
          (#t (%awk-p-err "unexpected token" toks)))))))

; Postfix ++/-- ride on a primary.
(def %awk-p-postfix
  (fn (_ toks gt)
    (def r (%awk-p-primary toks gt))
    (def ast (first r))
    (def ts (rest r))
    (if (if (%awk-p-op? ts "++") (%awk-p-lval? ast) #f)
      (pair (list (lit postinc) ast) (rest ts))
      (if (if (%awk-p-op? ts "--") (%awk-p-lval? ast) #f)
        (pair (list (lit postdec) ast) (rest ts))
        r))))

; ^ is right-associative and tighter than unary minus ON THE LEFT:
; -2^2 is -(2^2).  The primary already consumed a leading -, so that
; case parses as (neg (pow 2 2)) via primary recursing... it does not:
; primary wraps ONLY its operand.  So the ladder is: postfix, then ^
; recursing to the unary level on the right.
(def %awk-p-pow
  (fn (_ toks gt)
    (def r (%awk-p-postfix toks gt))
    (if (%awk-p-op? (rest r) "^")
      (let ((rhs (%awk-p-pow (rest (rest r)) gt)))
        (pair (list (lit pow) (first r) (first rhs)) (rest rhs)))
      r)))

; --- Binary ladders ----------------------------------------------------------

(def %awk-p-mul
  (fn (_ toks gt)
    (def go
      (fn (self ts left)
        (def s (if (%awk-p-op? ts "*") "*"
                 (if (%awk-p-op? ts "/") "/"
                   (if (%awk-p-op? ts "%") "%" ()))))
        (if (null? s) (pair left ts)
          (let ((r (%awk-p-pow (rest ts) gt)))
            (self (rest r) (list (lit bin) s left (first r)))))))
    (def r (%awk-p-pow toks gt))
    (go (rest r) (first r))))

(def %awk-p-add
  (fn (_ toks gt)
    (def go
      (fn (self ts left)
        (def s (if (%awk-p-op? ts "+") "+"
                 (if (%awk-p-op? ts "-") "-" ())))
        (if (null? s) (pair left ts)
          (let ((r (%awk-p-mul (rest ts) gt)))
            (self (rest r) (list (lit bin) s left (first r)))))))
    (def r (%awk-p-mul toks gt))
    (go (rest r) (first r))))

; Concatenation is juxtaposition: another operand simply begins.  The
; start set excludes + and - (the additive loop above owns those) and,
; because it IS an operand start, excludes nothing else that could open
; an expression.
(def %awk-p-concat-start?
  (fn (_ toks)
    (if (null? toks) #f
      (let ((tag (%awk-p-tag toks)))
        (match
          ((eq? tag (lit num)) #t)
          ((eq? tag (lit str)) #t)
          ((eq? tag (lit ere)) #t)
          ((eq? tag (lit name)) #t)
          ((eq? tag (lit funcname)) #t)
          ((eq? tag (lit op))
            (let ((s (first (rest (first toks)))))
              (if (string=? s "(") #t
                (if (string=? s "$") #t
                  (if (string=? s "!") #t
                    (if (string=? s "++") #t (string=? s "--")))))))
          (#t #f))))))

(def %awk-p-concat
  (fn (_ toks gt)
    (def go
      (fn (self ts left)
        (if (%awk-p-concat-start? ts)
          (let ((r (%awk-p-add ts gt)))
            (self (rest r) (list (lit concat) left (first r))))
          (pair left ts))))
    (def r (%awk-p-add toks gt))
    (go (rest r) (first r))))

; Relational: non-associative in awk (a < b < c is a syntax error in
; POSIX; here the second < simply ends the parse and the statement layer
; objects).  `>` only when the context allows it -- see the header.
(def %awk-p-rel
  (fn (_ toks gt)
    (def r (%awk-p-concat toks gt))
    (def ts (rest r))
    (def s (if (%awk-p-op? ts "<") "<"
             (if (%awk-p-op? ts "<=") "<="
               (if (%awk-p-op? ts "==") "=="
                 (if (%awk-p-op? ts "!=") "!="
                   (if (%awk-p-op? ts ">=") ">="
                     (if (if gt (%awk-p-op? ts ">") #f) ">" ())))))))
    (if (null? s) r
      (let ((rhs (%awk-p-concat (rest ts) gt)))
        (pair (list (lit cmp) s (first r) (first rhs)) (rest rhs))))))

(def %awk-p-match
  (fn (_ toks gt)
    (def go
      (fn (self ts left)
        (if (%awk-p-op? ts "~")
          (let ((r (%awk-p-rel (rest ts) gt)))
            (self (rest r) (list (lit match) left (first r))))
          (if (%awk-p-op? ts "!~")
            (let ((r (%awk-p-rel (rest ts) gt)))
              (self (rest r) (list (lit nomatch) left (first r))))
            (pair left ts)))))
    (def r (%awk-p-rel toks gt))
    (go (rest r) (first r))))

; `k in a` -- array membership, looser than match, tighter than &&.
; The right side is an array NAME, carried as a string.
(def %awk-p-in
  (fn (_ toks gt)
    (def go
      (fn (self ts left)
        (if (%awk-p-kw? ts (lit in))
          (if (eq? (%awk-p-tag (rest ts)) (lit name))
            (self (rest (rest ts))
              (list (lit in) left (first (rest (first (rest ts))))))
            (%awk-p-err "expected an array name after in" ts))
          (pair left ts))))
    (def r (%awk-p-match toks gt))
    (go (rest r) (first r))))

(def %awk-p-and
  (fn (_ toks gt)
    (def go
      (fn (self ts left)
        (if (%awk-p-op? ts "&&")
          (let ((r (%awk-p-in (%awk-p-skip-nl (rest ts)) gt)))
            (self (rest r) (list (lit and) left (first r))))
          (pair left ts))))
    (def r (%awk-p-in toks gt))
    (go (rest r) (first r))))

(def %awk-p-or
  (fn (_ toks gt)
    (def go
      (fn (self ts left)
        (if (%awk-p-op? ts "||")
          (let ((r (%awk-p-and (%awk-p-skip-nl (rest ts)) gt)))
            (self (rest r) (list (lit or) left (first r))))
          (pair left ts))))
    (def r (%awk-p-and toks gt))
    (go (rest r) (first r))))

(def %awk-p-ternary
  (fn (_ toks gt)
    (def r (%awk-p-or toks gt))
    (if (%awk-p-op? (rest r) "?")
      (let ((a (%awk-p-ternary (%awk-p-skip-nl (rest (rest r))) gt)))
        (if (%awk-p-op? (rest a) ":")
          (let ((b (%awk-p-ternary (%awk-p-skip-nl (rest (rest a))) gt)))
            (pair (list (lit ternary) (first r) (first a) (first b))
              (rest b)))
          (%awk-p-err "expected : in ?:" (rest a))))
      r)))

; Assignment: lowest, right-associative, only onto an l-value.  Compound
; forms desugar here -- `x += e` is `x = x + e` -- so the evaluator has
; ONE assignment to mean.  (The index of a field l-value evaluates twice
; under the desugaring; $(i++) += 1 is the corner where that shows.)
(def %awk-p-asgn-op
  (fn (_ toks)
    (if (%awk-p-op? toks "=") ""
      (if (%awk-p-op? toks "+=") "+"
        (if (%awk-p-op? toks "-=") "-"
          (if (%awk-p-op? toks "*=") "*"
            (if (%awk-p-op? toks "/=") "/"
              (if (%awk-p-op? toks "%=") "%"
                (if (%awk-p-op? toks "^=") "^" ())))))))))

(set! %awk-p-expr
  (fn (_ toks gt)
    (def r (%awk-p-ternary toks gt))
    (def op (%awk-p-asgn-op (rest r)))
    (if (null? op) r
      (if (%awk-p-lval? (first r))
        (let ((rhs (%awk-p-expr (%awk-p-skip-nl (rest (rest r))) gt)))
          (pair
            (list (lit assign) (first r)
              (match
                ((string=? op "") (first rhs))
                ((string=? op "^") (list (lit pow) (first r) (first rhs)))
                (#t (list (lit bin) op (first r) (first rhs)))))
            (rest rhs)))
        (%awk-p-err "assignment needs a variable or field" toks)))))

; --- Statements --------------------------------------------------------------

; A parenthesized condition: ( expr ) with newlines free inside.
(def %awk-p-cond
  (fn (_ toks what)
    (if (%awk-p-op? toks "(")
      (let ((r (%awk-p-expr (%awk-p-skip-nl (rest toks)) #t)))
        (if (%awk-p-op? (rest r) ")")
          (pair (first r) (rest (rest r)))
          (%awk-p-err (string-append "expected ) after " what) (rest r))))
      (%awk-p-err (string-append "expected ( after " what) toks))))

; print arguments: a comma-separated list, `>` refused (gt=#f), ended by a
; statement boundary.
(def %awk-p-print-args
  (fn (_ toks)
    (if (%awk-p-term? toks)
      (pair () toks)
      (let ((loop ()))
        (set! loop
          (fn (self ts acc)
            (def r (%awk-p-expr ts #f))
            (if (%awk-p-op? (rest r) ",")
              (self (%awk-p-skip-nl (rest (rest r))) (pair (first r) acc))
              (pair (reverse (pair (first r) acc)) (rest r)))))
        (loop toks ())))))

; The body statement after if/while/for/else: newlines may precede it.
(def %awk-p-body
  (fn (_ toks) (%awk-p-stmt (%awk-p-skip-nl toks))))

; The C-style for ladder: init ; cond ; update, each part optional.
; The caller has consumed `for (` and ruled out the for-in shape.
(def %awk-p-for-c
  (fn (_ ts)
    (def init (if (%awk-p-op? ts ";") (pair () ts)
                (%awk-p-expr ts #t)))
    (if (%awk-p-op? (rest init) ";")
      (let ((ts2 (%awk-p-skip-nl (rest (rest init)))))
        (def c (if (%awk-p-op? ts2 ";") (pair () ts2)
                 (%awk-p-expr ts2 #t)))
        (if (%awk-p-op? (rest c) ";")
          (let ((ts3 (%awk-p-skip-nl (rest (rest c)))))
            (def u (if (%awk-p-op? ts3 ")") (pair () ts3)
                     (%awk-p-expr ts3 #t)))
            (if (%awk-p-op? (rest u) ")")
              (let ((b (%awk-p-body (rest (rest u)))))
                (pair
                  (list (lit for) (first init) (first c) (first u)
                    (first b))
                  (rest b)))
              (%awk-p-err "expected ) in for" (rest u))))
          (%awk-p-err "expected second ; in for" (rest c))))
      (%awk-p-err "expected ; in for" (rest init)))))

(set! %awk-p-stmt
  (fn (_ toks)
    (match
      ((%awk-p-op? toks "{")
        (let ((r (%awk-p-stmts (rest toks) "}")))
          (if (%awk-p-op? (rest r) "}")
            (pair (list (lit block) (first r)) (rest (rest r)))
            (%awk-p-err "expected }" (rest r)))))
      ((%awk-p-kw? toks (lit print))
        (let ((r (%awk-p-print-args (rest toks))))
          (pair (pair (lit print) (first r)) (rest r))))
      ((%awk-p-kw? toks (lit printf))
        (let ((r (%awk-p-print-args (rest toks))))
          (if (null? (first r))
            (%awk-p-err "printf needs a format string" toks)
            (pair (pair (lit printf) (first r)) (rest r)))))
      ((%awk-p-kw? toks (lit if))
        (let ((c (%awk-p-cond (rest toks) "if")))
          (def t (%awk-p-body (rest c)))
          ; `else` may sit after newlines AND after the `;` that closed the
          ; then-branch (`print 1; else` is POSIX).  Peek past both and only
          ; commit the skip when else is really there.
          (def skip-sep
            (fn (self ts)
              (if (if (pair? ts) (eq? (first (first ts)) (lit nl)) #f)
                (self (rest ts))
                (if (%awk-p-op? ts ";") (self (rest ts)) ts))))
          (def peek (skip-sep (rest t)))
          (if (%awk-p-kw? peek (lit else))
            (let ((e (%awk-p-body (rest peek))))
              (pair (list (lit if) (first c) (first t) (first e)) (rest e)))
            (pair (list (lit if) (first c) (first t) ()) (rest t)))))
      ((%awk-p-kw? toks (lit while))
        (let ((c (%awk-p-cond (rest toks) "while")))
          (def b (%awk-p-body (rest c)))
          (pair (list (lit while) (first c) (first b)) (rest b))))
      ((%awk-p-kw? toks (lit do))
        (let ((b (%awk-p-body (rest toks))))
          (def peek (%awk-p-skip-nl (rest b)))
          (if (%awk-p-kw? peek (lit while))
            (let ((c (%awk-p-cond (rest peek) "do-while")))
              (pair (list (lit do) (first b) (first c)) (rest c)))
            (%awk-p-err "expected while after do body" peek))))
      ((%awk-p-kw? toks (lit for))
        (if (%awk-p-op? (rest toks) "(")
          (let ((ts (rest (rest toks))))
            ; for (NAME in NAME) is its own statement -- peek the exact
            ; four-token shape before committing to the C-style ladder.
            (def t2 (rest ts))
            (def t3 (if (pair? t2) (rest t2) ()))
            (def t4 (if (pair? t3) (rest t3) ()))
            (if (if (eq? (%awk-p-tag ts) (lit name))
                  (if (%awk-p-kw? t2 (lit in))
                    (if (eq? (%awk-p-tag t3) (lit name))
                      (%awk-p-op? t4 ")") #f) #f) #f)
              (let ((b (%awk-p-body (rest t4))))
                (pair
                  (list (lit for-in)
                    (first (rest (first ts)))
                    (first (rest (first t3)))
                    (first b))
                  (rest b)))
              (%awk-p-for-c ts)))
          (%awk-p-err "expected ( after for" (rest toks))))
      ((%awk-p-kw? toks (lit delete))
        (if (eq? (%awk-p-tag (rest toks)) (lit name))
          (let ((nm (first (rest (first (rest toks))))))
            (def ts (rest (rest toks)))
            (if (%awk-p-op? ts "[")
              (let ((r (%awk-p-subs (rest ts))))
                (pair (list (lit delete) nm (first r)) (rest r)))
              (pair (list (lit delete) nm ()) ts)))
          (%awk-p-err "expected an array name after delete" (rest toks))))
      ((%awk-p-kw? toks (lit return))
        (if (%awk-p-term? (rest toks))
          (pair (list (lit return) ()) (rest toks))
          (let ((r (%awk-p-expr (rest toks) #t)))
            (pair (list (lit return) (first r)) (rest r)))))
      ((%awk-p-kw? toks (lit next)) (pair (list (lit next)) (rest toks)))
      ((%awk-p-kw? toks (lit break)) (pair (list (lit break)) (rest toks)))
      ((%awk-p-kw? toks (lit continue))
        (pair (list (lit continue)) (rest toks)))
      ((%awk-p-kw? toks (lit exit))
        (if (%awk-p-term? (rest toks))
          (pair (list (lit exit) ()) (rest toks))
          (let ((r (%awk-p-expr (rest toks) #t)))
            (pair (list (lit exit) (first r)) (rest r)))))
      ((%awk-p-op? toks ";") (pair (list (lit block) ()) (rest toks)))
      (#t
        (let ((r (%awk-p-expr toks #t)))
          (pair (list (lit expr) (first r)) (rest r)))))))

; Statements until the closing token (or the end), separators skipped.
(set! %awk-p-stmts
  (fn (_ toks closer)
    (def sep?
      (fn (_ ts)
        (if (if (pair? ts) (eq? (first (first ts)) (lit nl)) #f) #t
          (%awk-p-op? ts ";"))))
    (def go
      (fn (self ts acc)
        (def ts1
          (if (sep? ts)
            (let ((skip (fn (self2 t2)
                          (if (sep? t2) (self2 (rest t2)) t2))))
              (skip ts))
            ts))
        (if (null? ts1) (pair (reverse acc) ts1)
          (if (%awk-p-op? ts1 closer) (pair (reverse acc) ts1)
            (let ((r (%awk-p-stmt ts1)))
              (self (rest r) (pair (first r) acc)))))))
    (go toks ())))

; --- Items -------------------------------------------------------------------

; BEGIN { ... } | END { ... } | pattern { ... } | pattern | { ... }
(def %awk-p-action
  (fn (_ toks)
    (if (%awk-p-op? toks "{")
      (let ((r (%awk-p-stmts (rest toks) "}")))
        (if (%awk-p-op? (rest r) "}")
          (pair (first r) (rest (rest r)))
          (%awk-p-err "expected }" (rest r))))
      (%awk-p-err "expected {" toks))))

; function NAME(p1, p2, ...) { body } -- the parameter list is names
; only; extras beyond the call's arguments are the function's locals.
(def %awk-p-func
  (fn (_ toks)
    (def t2 (rest toks))
    (def nm
      (match
        ((eq? (%awk-p-tag t2) (lit funcname)) (first (rest (first t2))))
        ((eq? (%awk-p-tag t2) (lit name)) (first (rest (first t2))))
        (#t (%awk-p-err "expected a function name" t2))))
    (def t3 (rest t2))
    (if (not (%awk-p-op? t3 "("))
      (%awk-p-err "expected ( after the function name" t3)
      (let ((params ()))
        (def go
          (fn (self ts acc)
            (match
              ((%awk-p-op? ts ")") (pair (reverse acc) (rest ts)))
              ((eq? (%awk-p-tag ts) (lit name))
                (let ((ts2 (rest ts)))
                  (if (%awk-p-op? ts2 ",")
                    (self (%awk-p-skip-nl (rest ts2))
                      (pair (first (rest (first ts))) acc))
                    (self ts2 (pair (first (rest (first ts))) acc)))))
              (#t (%awk-p-err "expected a parameter name or )" ts)))))
        (def pr (go (rest t3) ()))
        (def br (%awk-p-action (%awk-p-skip-nl (rest pr))))
        (pair (list (lit func) nm (first pr) (first br)) (rest br))))))

(def %awk-p-item
  (fn (_ toks)
    (match
      ((%awk-p-kw? toks (lit function)) (%awk-p-func toks))
      ((%awk-p-kw? toks (lit BEGIN))
        (let ((r (%awk-p-action (%awk-p-skip-nl (rest toks)))))
          (pair (list (lit begin) (first r)) (rest r))))
      ((%awk-p-kw? toks (lit END))
        (let ((r (%awk-p-action (%awk-p-skip-nl (rest toks)))))
          (pair (list (lit end) (first r)) (rest r))))
      ((%awk-p-op? toks "{")
        (let ((r (%awk-p-action toks)))
          (pair (list (lit rule) () (first r)) (rest r))))
      (#t
        (let ((p (%awk-p-expr toks #t)))
          (if (%awk-p-op? (rest p) "{")
            (let ((r (%awk-p-action (rest p))))
              (pair (list (lit rule) (first p) (first r)) (rest r)))
            (pair (list (lit rule) (first p) ()) (rest p))))))))

(def awk-parse
  (fn (_ src)
    (def toks (awk-tokenize src))
    (def go
      (fn (self ts acc)
        (def ts1 (%awk-p-skip-nl ts))
        (def ts2 (if (%awk-p-op? ts1 ";") (rest ts1) ts1))
        (if (null? ts2)
          (reverse acc)
          (if (eq? ts2 ts)
            (let ((r (%awk-p-item ts2)))
              (self (rest r) (pair (first r) acc)))
            (self ts2 acc)))))
    (go toks ())))

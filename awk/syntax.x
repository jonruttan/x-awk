; # x-awk -- POSIX awk on x-lang
;
; ## awk/syntax.x -- the awk highlighting grammar
;
; @description The grammar x/tool/syntax colours awk programs with: comments,
;   strings, regular expressions, numbers, keywords, builtins and awk's own
;   variables.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; lang.xon's (grammar awk ...) form names this module, and x/tool/syntax
; imports it the first time a file needs the grammar, in whatever process is
; colouring: vi's, a REPL's, an HTML renderer's.  So it imports x-lang
; libraries and awk/words only, never the interpreter.  Its keywords,
; builtins and operators are awk/words', the ones awk/lex and awk/parse read.
;
; A / divides after an operand and starts a regular expression anywhere
; else, as awk/lex reads it.  The Lexer has no context to carry that, so an
; operand -- a name, a number, a ) or a ] -- with the / after it is one
; token, its pieces the operand's and the operator; a / that no operand comes
; before opens a regular expression, its body taking \ escapes and a bracket
; expression, which may hold a /.  One left unclosed is no regular
; expression, and its / an operator.
;
; A string still open at the end of the text runs to it, as a line being
; typed leaves it.  A keyword is a keyword, a builtin a name, a variable awk
; sets a constant.  A brace, a bracket, a comma or a semicolon is
; punctuation, every other operator an operator.  Nothing in awk spans a
; line, so every line starts outside a string or comment.

(module awk/syntax)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors str-byte-ref char->int str-byte-len int+ int-)
(import awk/words awk-keywords awk-builtins awk-variables awk-ops2)

(def %awk-syntax-blanks (list 32 9 13 10 12 11))
(def %awk-syntax-name-start (list (pair 97 122) (pair 65 90) 95))
(def %awk-syntax-name-rest (list (pair 97 122) (pair 65 90) (pair 48 57) 95))
; an operand's bytes: a name's, a number's, and the brackets that close one
(def %awk-syntax-operand (list (pair 97 122) (pair 65 90) (pair 48 57) 95 46 41 93))

(def %awk-syntax-ops
  (List append awk-ops2
    (list "{" "}" "(" ")" "[" "]" ";" "," "+" "-" "*" "/" "%" "^" "!" "<"
          ">" "|" "?" ":" "~" "$" "=")))

(def awk-syntax-rules
  (fn (_)
    (list (Lexer run (lit blank) %awk-syntax-blanks %awk-syntax-blanks)
          (Lexer until (lit comment) "#" "\n" (lit to-end))
          (Lexer nested (lit string) "\"" (lit body)
            (list (list (lit body) 34 92 ())) (lit to-end))
          (Lexer nested (lit ere) "/" (lit body)
            (list (list (lit body) 47 92 (list (pair "[" (lit bracket))))
                  (list (lit bracket) 93 92 ())))
          (Lexer pattern (lit divide)
            (list (list %awk-syntax-operand 1 ()) (list " \t" 0 ()) (list "/" 1 1)))
          (Lexer run (lit name) %awk-syntax-name-start %awk-syntax-name-rest)
          (Lexer number (lit number) ())
          (Lexer table (lit op) %awk-syntax-ops)
          (Lexer any (lit plain)))))

(def %awk-syntax-byte (fn (_ s i) (char->int (str-byte-ref s i))))
(def %awk-syntax-digit? (fn (_ b) (if (>= b 48) (<= b 57) #f)))
; a byte of a name or a number
(def %awk-syntax-word?
  (fn (_ b)
    (match
      ((if (>= b 97) (<= b 122) #f) #t)
      ((if (>= b 65) (<= b 90) #f) #t)
      ((%awk-syntax-digit? b) #t)
      (#t (if (= b 95) #t (= b 46))))))
(def %awk-syntax-blank? (fn (_ b) (if (= b 32) #t (= b 9))))

(def %awk-syntax-name-class
  (fn (_ text)
    (match
      ((List includes? text awk-keywords) (lit keyword))
      ((List includes? text awk-builtins) (lit name))
      ((List includes? text awk-variables) (lit constant))
      (#t ()))))

; The end of the run of name and number bytes from I in S
(def %awk-syntax-word-end
  (fn (self s i n)
    (if (if (< i n) (%awk-syntax-word? (%awk-syntax-byte s i)) #f) (self s (int+ i 1) n) i)))

; Each ) or ] from I in S before N, punctuation
(def %awk-syntax-closers
  (fn (self s i n)
    (if (>= i n) ()
      (if (%awk-syntax-word? (%awk-syntax-byte s i)) (self s (int+ i 1) n)
        (if (%awk-syntax-blank? (%awk-syntax-byte s i)) (self s (int+ i 1) n)
          (pair (list i 1 (lit punct)) (self s (int+ i 1) n)))))))

; An operand and its /: the word's class, its closing brackets, the operator
(def %awk-syntax-divide-class
  (fn (_ text)
    (let ((n (str-byte-len text)))
      (let ((w (%awk-syntax-word-end text 0 n)))
        (let ((b (%awk-syntax-byte text 0)))
          (List append
            (if (= w 0) ()
              (list (list 0 w
                      (if (if (%awk-syntax-digit? b) #t (= b 46)) (lit number)
                        (%awk-syntax-name-class (Str8 sub 0 w text))))))
            (%awk-syntax-closers text w (int- n 1))
            (list (list (int- n 1) 1 (lit operator)))))))))

; { } ( ) [ ] ; ,
(def %awk-syntax-punct (list 123 125 40 41 91 93 59 44))

(def %awk-syntax-op-class
  (fn (_ text)
    (if (if (= (str-byte-len text) 1) (List includes? (%awk-syntax-byte text 0) %awk-syntax-punct) #f)
      (lit punct)
      (lit operator))))

(Syntax register!
  (let ((g (Syntax make (lit awk) (awk-syntax-rules)
             (list (pair (lit comment) (lit comment))
                   (pair (lit string) (lit string))
                   (pair (lit ere) (lit string))
                   (pair (lit number) (lit number))
                   (pair (lit divide) %awk-syntax-divide-class)
                   (pair (lit name) %awk-syntax-name-class)
                   (pair (lit op) %awk-syntax-op-class)))))
    (g sync (fn (_ s ls) #t))
    g))

(provide awk/syntax awk-syntax-rules)

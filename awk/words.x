; # x-awk -- POSIX awk on x-lang
;
; ## awk/words.x -- awk's keywords, builtins, variables and operators
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The words both readers of awk share: awk/lex and awk/parse, which read a
; program to run it, and awk/syntax, which colours it.  Data only, importing
; nothing, so a process colouring a file loads it without the interpreter.

(module awk/words)

(def awk-keywords
  (list "BEGIN" "END" "function" "if" "else" "while" "for" "do"
        "break" "continue" "next" "exit" "return" "delete" "in"
        "print" "printf" "getline"))

; The builtins the parser reads as calls.  `length` alone (no parens) is
; also legal awk.
(def awk-builtins
  (list "length" "substr" "index" "int" "split" "sprintf" "sub" "gsub"
        "match" "toupper" "tolower" "sin" "cos" "atan2" "exp" "log" "sqrt"
        "rand" "srand" "close" "system"))

; The variables awk sets
(def awk-variables
  (list "FS" "OFS" "ORS" "RS" "NR" "NF" "FILENAME" "FNR" "SUBSEP" "OFMT"
        "CONVFMT" "RSTART" "RLENGTH" "ARGC" "ARGV" "ENVIRON"))

; The operators of two bytes; every other operator is one
(def awk-ops2
  (list "==" "!=" "<=" ">=" "&&" "||" "++" "--"
        "+=" "-=" "*=" "/=" "%=" "^=" "!~" ">>"))

(provide awk/words awk-keywords awk-builtins awk-variables awk-ops2)

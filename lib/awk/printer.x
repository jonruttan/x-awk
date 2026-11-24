; # x-awk -- POSIX awk on x-lang
;
; ## awk/printer.x -- how awk shows a result
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; An awk run prints what its print statements printed, and that has already
; gone to stdout by the time a result comes back, so this printer is mostly
; quiet -- nil prints nothing.
;
; Symbols write bare: x's writer quotes them so an echo pastes back, so a
; token list would render as (('num "1")) where the specs assert ((num "1")).
; Lang symbols-bare! sets that on the symbol type, for write and
; write-to-str alike.

(module awk/printer)
(import x/repl/lang)

(Lang symbols-bare!)

(def awk-repl-print
  (fn (_ result)
    (unless (null? result) (write result))
    (newline)))

(provide awk/printer awk-repl-print)

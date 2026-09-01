; # x-awk -- POSIX awk on x-lang
;
; ## awk/printer.x -- how awk shows a result
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; AWK IS NOT A LISP: what an awk run prints is what its print statements
; printed, and that has already gone to stdout by the time a result comes
; back.  So this printer is mostly quiet -- nil prints nothing.
;
; THAT SAID, awk still needs its own `write`, for the same reason every
; bundle does: x's is round-trippable, so a token list renders as
; (('num "1")) rather than ((num "1")).  The specs assert the second --
; fifth bundle, same twenty lines (x-lang#518).

(provide awk/printer %awk-repl-print %awk-write)

(def %awk-write ())
(def %x-write write)
(def %awk-write-items
  (fn (_ v)
    (%awk-write (first v))
    (if (null? (rest v))
      ()
      (if (pair? (rest v))
        (%seq (display " ") (%awk-write-items (rest v)))
        (%seq (display " . ") (%awk-write (rest v)))))))
(set! %awk-write
  (fn (_ v)
    (if (pair? v)
      (%seq (display "(") (%seq (%awk-write-items v) (display ")")))
      (if (symbol? v) (display v) (%x-write v)))))
(def write %awk-write)

(def %awk-repl-print
  (fn (_ result)
    (unless (null? result) (%awk-write result))
    (newline)))

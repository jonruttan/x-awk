; # x-awk -- POSIX awk on x-lang
;
; ## lib/awk/run.x -- the entry
;
; @description A POSIX awk: pattern-action rules over records and fields,
;   its own lexer and recursive-descent parser, on x-lang's evaluator.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Usage:
;   x -l awk               interactive
;   x -l awk -f prog.x     batch (x forms driving the awk core)
;
; The module awk/run.  x.sh boots the dialect bundle.xon declares, arms the
; bundle's lib/ with import-path!, imports this module and calls its main, so
; `import` below resolves against the bundle wherever it sits.
(module awk/run)
(import awk/base awk-version)
(import awk/cli awk-main)
(import awk/printer awk-repl-print)
(set! %lang-name "AWK")
(set! %lang-version awk-version)
(set! %repl-prompt "awk> ")
(set! %repl-print awk-repl-print)

; With operands, awk-main runs them; with none the session goes on to the
; REPL or to the -f files.
(def main
  (fn (_)
    (let ((ops (rest (Sys args (lit program)))))
      (unless (null? ops) (awk-main ops)))))

(provide awk/run main)

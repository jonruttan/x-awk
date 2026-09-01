; # x-awk -- POSIX awk on x-lang
;
; ## run.x -- THE entry
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
; THIS FILE KNOWS NO PATHS.  x.sh boots the dialect lang.xon declares, arms
; this bundle's root with import-path!, cats this file, and appends the
; launcher when no -f was given.  By the time anything below runs, `import`
; resolves against the bundle wherever it happens to sit.
(import awk/base)

(set! %lang-name "AWK")
(set! %lang-version awk-version)
(set! %repl-prompt "awk> ")
(set! %repl-print %awk-repl-print)

; THE CLI: operands after the lang selection mean "be awk" --
;
;   x -l awk -- [-F ere] [-v a=v]... [-f prog.awk | 'program'] [file]...
;
; awk-main runs the program over the files (stdin when none) and EXITS,
; so the launcher x.sh appends never starts a REPL underneath a batch
; run.  No operands means the x REPL with the awk core loaded --
; awk-run, awk-tokenize and friends at a prompt.
(unless (null? (awk-argv args))
  (awk-main args))

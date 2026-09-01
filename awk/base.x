; # x-awk -- POSIX awk on x-lang
;
; ## awk/base.x -- the language, assembled
;
; @description A POSIX awk: lexer, parser, evaluator, on x-lang's evaluator.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; No path literals and no dialect boot here: run.x owns both (and the spec
; harness stands in for run.x under the suite).  Nothing under awk/ includes
; a platform module -- re-including one on a booted tower is a segfault, not
; an error (x-lang#515).
;
; THE LEXER IS A STRING SCANNER, NOT A READER BASE, and the choice is
; positive, not a workaround.  docs/crafting-a-lang.md makes the case for
; the engine's analyse/read loop, and its case is DELIMITATION: brackets,
; blocks, indentation -- regions that collect themselves.  awk's token
; stream is flat; its one lexing subtlety is that `/` divides or opens an
; ERE depending on the PREVIOUS token, which is exactly the context a
; per-character analyse callback cannot see and a scanner threads as one
; boolean.  Precedence stays in a recursive-descent ladder either way
; (the same doc, "what the reader cannot do").  So: string-ref down the
; source, the lib/x/type/regex.x shape.

(import awk/prims)
(import awk/printer)

(provide awk/base awk-version awk-tokenize awk-parse awk-run %awk-repl-print)

(def awk-version "0.1.0")

(include-once "./lex.x")
(include-once "./parse.x")
(include-once "./eval.x")

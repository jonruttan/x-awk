; # x-awk -- POSIX awk on x-lang
;
; ## awk/base.x -- the language, assembled
;
; @description A POSIX awk: lexer, parser, evaluator, on x-lang's evaluator.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; No path literals and no dialect boot here: run.x owns both (the spec harness
; stands in for run.x under the suite). Nothing under awk/ includes a platform
; module -- re-including one on a booted tower crashes rather than raising
; (x-lang#515).
;
; The lexer is a string scanner, not a reader base. The engine's analyse/read
; loop (docs/crafting-a-lang.md) is for delimitation -- brackets, blocks,
; indentation -- and awk's token stream is flat; its one subtlety is that `/`
; divides or opens an ERE depending on the previous token, which a
; per-character analyse callback cannot see and a scanner threads as one
; boolean. So: string-ref down the source, the lib/x/type/regex.x shape.

(import awk/prims)
(import awk/printer)

(provide awk/base awk-version awk-tokenize awk-parse awk-run
  awk-argv awk-parse-cli awk-main %awk-repl-print)

(def awk-version "0.1.0")

(include-once "./lex.x")
(include-once "./parse.x")
(include-once "./eval.x")
(include-once "./fmt.x")
(include-once "./cli.x")

; # x-awk -- POSIX awk on x-lang
;
; ## awk/prims.x -- the platform layer, under the names awk is written against
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; ONE FILE between awk and the platform, so the lexer, parser and evaluator
; read as what they are.  Everything here goes through the public classes
; (Str8, List, Regex) or the prim catalog -- never a platform %-private;
; the seam table in docs/lang-contract.md is the whole contract.
;
; x/type/regex comes in HERE: awk's ERE literals, ~ matching, and the
; dynamic regexes built from strings all ride (Regex compile) and the
; Regex exec methods.  This import is also what fixes the dialect floor.

(import x/type/regex)

(provide awk/prims
  char->integer integer->char
  string-length string-ref substring string-append string-concat
  string=? string? make-string list->string convert
  length reverse append map filter nth set-first!
  regex-compile regex-search regex-split regex-replace-all)

; THE DIRECT PRIMS, NOT THE CONVERT DISPATCHER, for the two casts the lexer
; makes per character: the dispatching version walks type alists and
; allocates, and lib/x/reader/analyser.x holds the same references for the
; same reason.  Note the namespaces: conversions key on the SOURCE type,
; so the pair is (char ->int) and (int ->char).
(def char->integer (prim-ref (lit char) (lit ->int)))
(def integer->char (prim-ref (lit int) (lit ->char)))

(def string-length (fn (_ s) (Str8 length s)))
(def string-ref (fn (_ s i) (Str8 ref i s)))
; Scheme's substring is [start, end); Str8 sub is (start, LENGTH).
(def substring (fn (_ s a b) (Str8 sub a (- b a) s)))
(def string=? (fn (_ a b) (str=? a b)))
(def string? (fn (_ s) (str? s)))
(def make-string (fn (_ n c) (Str8 make n c)))

(def %cvt (prim-ref (lit convert) (lit to)))
(def list->string (fn (_ l) (if (null? l) "" (%cvt l %string))))
; NO EXPLICIT RECEIVER: every call fills the `_` slot implicitly, `apply`
; included, so passing one by hand shifts every argument along.
(def convert (fn (_ v target . extra) (apply %cvt (pair v (pair target extra)))))

(def string-append (fn (_ . ss) (string-concat ss)))
; Pairwise append is O(n^2) in the piece count; fine at awk-output scale,
; replace with a rope the day a spec says so.
(def string-concat
  (fn (self ss)
    (if (null? ss)
      ""
      (if (null? (rest ss)) (first ss) (Str8 append (first ss) (self (rest ss)))))))

(def length (fn (_ l) (List length l)))
(def reverse (fn (_ l) (%awk-rev l ())))
(def %awk-rev
  (fn (self l acc)
    (if (null? l) acc (self (rest l) (pair (first l) acc)))))
(def append (fn (_ a b) (List append a b)))
(def map (fn (_ f l) (List map f l)))
(def filter (fn (_ p l) (List filter p l)))
(def nth (fn (_ n l) (List ref n l)))
; The one mutation door the evaluator uses: variable boxes are one-cell
; lists updated in place.  The same alias ash/prims.x carries.
(def set-first! %set-first!)

; --- Regex, the awk way ------------------------------------------------------
; awk builds regexes from strings at runtime (`$0 ~ v` where v holds a
; pattern), so everything routes through (Regex compile).  The parser
; compiles each /ere/ literal ONCE at parse time and the AST carries the
; compiled value.
(def regex-compile (fn (_ pattern) (Regex compile pattern)))
(def regex-search (fn (_ s rx) (Regex search s rx)))
(def regex-split (fn (_ s rx) (Regex split s rx)))
(def regex-replace-all (fn (_ s rep rx) (Regex replace-all s rep rx)))

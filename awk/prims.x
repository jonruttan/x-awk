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
; The math set rides the platform's libm-backed floats, and rand rides its
; xorshift PRNG.  Floats never enter awk's value model: eval.x converts at
; the builtin boundary (rational in, printed digits back to rational out).
(import x/num/float)
(import x/num/random)
; The CLI front's doors: files, processes, and the exit.  These are the
; radon capabilities the dialect row has reserved all along.
(import x/sys/file)
(import x/sys/proc)

(provide awk/prims
  char->integer integer->char
  string-length string-ref substring string-append string-concat
  string=? string? make-string list->string convert
  length reverse append map filter nth set-first!
  regex-compile regex-search regex-split regex-replace-all regex-find-at
  float-from float->string float-sin float-cos float-exp float-log
  float-sqrt float-atan2 make-rng rng-int
  file-open-write file-open-append file-close file-write
  file-read-all file-read-fd file-exists? file-unlink
  proc-run sys-exit sys-dup2 sys-close)

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
(def regex-find-at (fn (_ s pos rx) (Regex find-at s pos rx)))

; --- The float boundary ------------------------------------------------------
; (Float from) takes any exact number; the transcendentals are libm.
(def float-from (fn (_ x) (Float from x)))
(def float->string (fn (_ f) (%cvt f %string)))
(def float-sin (fn (_ f) (Float sin f)))
(def float-cos (fn (_ f) (Float cos f)))
(def float-exp (fn (_ f) (Float exp f)))
(def float-log (fn (_ f) (Float log f)))
(def float-sqrt (fn (_ f) (Float sqrt f)))
(def float-atan2 (fn (_ y x) (Float atan2 y x)))

; --- The PRNG ----------------------------------------------------------------
; (Random sw seed) is deterministic xorshift; (rng int n) answers [0, n).
(def make-rng (fn (_ seed) (Random sw seed)))
(def rng-int (fn (_ r n) (r int n)))

; --- Files, processes, the exit ----------------------------------------------
(def file-open-write
  (fn (_ path) (File open path (list (lit wronly) (lit creat) (lit trunc)))))
(def file-open-append
  (fn (_ path) (File open path (list (lit wronly) (lit creat) (lit append)))))
(def file-close (fn (_ fd) (File close fd)))
; (File read)/(File write) are the raw syscall shapes: read fills a
; buffer you allocate and answers the byte COUNT (0 at EOF); write
; wants an explicit size.  These wrappers speak strings.
(def file-write
  (fn (_ fd s) (File write fd s (string-length s))))
(def file-read-all (fn (_ path) (File read-all path)))
(def file-read-fd
  (fn (_ fd n)
    (def buf (make-string n (integer->char 0)))
    (def r (File read fd buf n))
    (if (if (number? r) (> r 0) #f) (substring buf 0 r) "")))
(def file-exists? (fn (_ path) (File exists? path)))
(def file-unlink (fn (_ path) (File unlink path)))
; system(cmd) is the shell's reading of cmd, wait included.
(def proc-run (fn (_ argv) (Proc run! argv)))
(def sys-exit (fn (_ n) (Sys exit n)))
(def sys-dup2 (fn (_ a b) (Sys dup2 a b)))
(def sys-close (fn (_ fd) (Sys close fd)))

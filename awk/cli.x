; # x-awk -- POSIX awk on x-lang
;
; ## awk/cli.x -- the command line
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The invocation is  x -l awk -- [-F ere] [-v a=v]... [-f progfile]...
;                    ['program'] [file | a=v]...
; The `--` matters: x.sh's own option loop claims -F, -v and -f, and `--` is
; the first token it declines, so everything after arrives here untouched.
; Without `--` the same options work placed after the program text, since x.sh
; stops at the first non-option operand.
;
; Parsing is split pure/effectful on the spec seam: awk-argv and awk-parse-cli
; are pure functions the suite exercises; awk-main is the few effectful lines
; that read progfiles, run, and exit.

; The engine flags x.sh plants ahead of the operands, plus argv0.
(def %awk-cli-engine-flag?
  (fn (_ s)
    (if (string=? s "--quiet") #t
      (if (string=? s "--batch") #t
        (if (string=? s "--no-color") #t (string=? s "--verbose"))))))

; The raw engine args to awk's own operands: drop argv0, drop the
; engine's flags, drop one leading --.
(def awk-argv
  (fn (_ raw)
    (def ops
      (filter (fn (_ a) (not (%awk-cli-engine-flag? a)))
        (if (pair? raw) (rest raw) ())))
    (if (if (pair? ops) (string=? (first ops) "--") #f)
      (rest ops)
      ops)))

; The options, declared once: what the parse accepts, what --help prints and
; what a refusal prints.  busybox's awk help text, less the -E spelling and the
; -e row for options this awk does not take.
(def %awk-options
  (Opts declare "awk" "[OPTIONS] [AWK_PROGRAM] [FILE]..." ()
    (list
      (Opts arg "-v" "VAR=VAL" "Set variable")
      (Opts arg "-F" "SEP" "Use SEP as field separator")
      (Opts arg "-f" "FILE" "Read program from FILE"))))

; Operands to a plan:
;   ((fs . FS|()) (assigns . ((name . value) ...)) (progfiles . (path ...))
;    (prog . text|()) (argv . (operand ...)))
; or nil when the line does not run: an option awk does not take, or a -v
; that is not name=value.  Options stop at the first operand, as musl's getopt
; stops; a -F given twice keeps the last.  -f wins over a program operand,
; POSIX's rule; assigns keep order.
(def awk-parse-cli
  (fn (_ operands)
    (def o (Opts parse-leading %awk-options operands))
    (def ops (Opts operands o))
    (def progfiles (Opts values o "-f"))
    (def assigns
      (fn (self vs)
        (if (null? vs) ()
          (let ((eq-at (%awk-str-index (first vs) "=")))
            (if (= eq-at 0) (lit bad)
              (let ((more (self (rest vs))))
                (if (eq? more (lit bad)) more
                  (pair (pair (substring (first vs) 0 (- eq-at 1))
                              (substring (first vs) eq-at (string-length (first vs))))
                        more))))))))
    (def as (assigns (Opts values o "-v")))
    (if (if (null? (Opts unknown o)) (not (eq? as (lit bad))) #f)
      (list (pair (lit fs) (Opts value o "-F"))
        (pair (lit assigns) as)
        (pair (lit progfiles) progfiles)
        (pair (lit prog) (if (if (null? progfiles) (pair? ops) #f) (first ops) ()))
        (pair (lit argv) (if (if (null? progfiles) (pair? ops) #f) (rest ops) ops)))
      ())))

; The line refused, as busybox's awk refuses it: musl getopt's line naming the
; option, or nothing for a bad -v or no program, then the usage text, on
; standard error, and 1.  awk takes no long options, so --NAME is the option -.
(def %awk-refuse
  (fn (_ tok)
    (do (file-write 2
          (string-concat
            (list (if (null? tok) "" (string-append "awk: " (string-append (%awk-refusal tok) "\n")))
                  (Opts usage %awk-options))))
        1)))

(def %awk-refusal
  (fn (_ tok)
    (def end (string-length tok))
    (def go
      (fn (self i)
        (let ((opt (string-append "-" (substring tok i (+ i 1)))))
          (match
            ((>= i end) (string-append "unrecognized option: " (substring tok 1 end)))
            ((%awk-cli-member? opt (Opts valued %awk-options))
              (string-append "option requires an argument: " (substring tok i (+ i 1))))
            (#t (string-append "unrecognized option: " (substring tok i (+ i 1))))))))
    (if (if (> end 2) (= (string-ref tok 1) #\-) #f) "unrecognized option: -" (go 1))))

(def %awk-cli-member?
  (fn (self s l)
    (if (null? l) #f (if (string=? (first l) s) #t (self s (rest l))))))

(def %awk-cli-get
  (fn (_ key plan)
    (def go
      (fn (self ps)
        (if (null? ps) ()
          (if (eq? (first (first ps)) key)
            (rest (first ps))
            (self (rest ps))))))
    (go plan)))

; Run the command line and DO NOT RETURN: the exit status is exit's
; value when the program called it, else 0.  --help first prints the help
; text, and 0; a line that does not run is refused, and 1.
(def awk-main
  (fn (_ raw-args)
    (def argv (awk-argv raw-args))
    (def plan (if (Opts help? %awk-options argv) () (awk-parse-cli argv)))
    (def progfiles (%awk-cli-get (lit progfiles) plan))
    (def prog
      (if (null? progfiles)
        (%awk-cli-get (lit prog) plan)
        (let ((join ()))
          (set! join
            (fn (self fs)
              (if (null? fs) ""
                (string-append (file-read-all (first fs))
                  (string-append "\n" (self (rest fs)))))))
          (join progfiles))))
    (match
      ((Opts help? %awk-options argv)
        (do (display (Opts usage %awk-options)) (sys-exit 0)))
      ((null? plan)
        (sys-exit (%awk-refuse (Opts unknown (Opts parse-leading %awk-options argv)))))
      ((null? prog) (sys-exit (%awk-refuse ())))
      (#t (sys-exit
            (%awk-run-cli prog
              (%awk-cli-get (lit fs) plan)
              (%awk-cli-get (lit assigns) plan)
              (%awk-cli-get (lit argv) plan)))))))

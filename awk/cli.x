; # x-awk -- POSIX awk on x-lang
;
; ## awk/cli.x -- the command line
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; THE INVOCATION IS  x -l awk -- [-F ere] [-v a=v]... [-f progfile]...
;                    ['program'] [file | a=v]...
; The `--` matters: x.sh's own option loop claims -F, -v and -f for
; itself, and `--` is the first token it declines -- everything after it
; arrives here untouched.  Without `--` the same options still work
; PLACED AFTER the program text, since x.sh stops at the first
; non-option operand.
;
; Parsing is split pure/effectful on the spec seam: awk-argv and
; awk-parse-cli are pure functions the suite exercises; awk-main is the
; few effectful lines that read progfiles, run, and exit.

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

; One operand: does it look like -Xvalue / -X value?  Answers the value
; and the rest, from the joined or the split spelling.
(def %awk-cli-optarg
  (fn (_ op ops)
    (if (> (string-length op) 2)
      (pair (substring op 2 (string-length op)) (rest ops))
      (if (null? (rest ops))
        (Err raise (lit awk)
          (string-append "awk: option needs an argument: " op) ())
        (pair (first (rest ops)) (rest (rest ops)))))))

; Operands to a plan:
;   ((fs . FS|()) (assigns . ((name . value) ...)) (progfiles . (path ...))
;    (prog . text|()) (argv . (operand ...)))
; -f wins over a program operand, POSIX's rule; assigns keep order.
(def awk-parse-cli
  (fn (_ operands)
    (def go
      (fn (self ops fs assigns progfiles)
        (match
          ((null? ops)
            (list (pair (lit fs) fs)
              (pair (lit assigns) (reverse assigns))
              (pair (lit progfiles) (reverse progfiles))
              (pair (lit prog) ())
              (pair (lit argv) ())))
          ((let ((op (first ops)))
             (if (>= (string-length op) 2)
               (if (= (string-ref op 0) #\-) (= (string-ref op 1) #\F) #f)
               #f))
            (let ((r (%awk-cli-optarg (first ops) ops)))
              (self (rest r) (first r) assigns progfiles)))
          ((let ((op (first ops)))
             (if (>= (string-length op) 2)
               (if (= (string-ref op 0) #\-) (= (string-ref op 1) #\v) #f)
               #f))
            (let ((r (%awk-cli-optarg (first ops) ops)))
              (def eq-at (%awk-str-index (first r) "="))
              (if (= eq-at 0)
                (Err raise (lit awk)
                  (string-append "awk: -v needs name=value: " (first r)) ())
                (self (rest r)
                  fs
                  (pair (pair (substring (first r) 0 (- eq-at 1))
                          (substring (first r) eq-at
                            (string-length (first r))))
                    assigns)
                  progfiles))))
          ((let ((op (first ops)))
             (if (>= (string-length op) 2)
               (if (= (string-ref op 0) #\-) (= (string-ref op 1) #\f) #f)
               #f))
            (let ((r (%awk-cli-optarg (first ops) ops)))
              (self (rest r) fs assigns (pair (first r) progfiles))))
          ; first non-option: the program text (unless -f already gave
          ; one), then everything else verbatim
          (#t
            (let ((have-f (not (null? progfiles))))
              (list (pair (lit fs) fs)
                (pair (lit assigns) (reverse assigns))
                (pair (lit progfiles) (reverse progfiles))
                (pair (lit prog) (if have-f () (first ops)))
                (pair (lit argv) (if have-f ops (rest ops)))))))))
    (go operands () () ())))

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
; value when the program called it, else 0.
(def awk-main
  (fn (_ raw-args)
    (def plan (awk-parse-cli (awk-argv raw-args)))
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
    (if (null? prog)
      (Err raise (lit awk)
        "usage: x -l awk -- [-F ere] [-v a=v]... [-f progfile | 'program'] [file | a=v]..."
        ())
      (sys-exit
        (%awk-run-cli prog
          (%awk-cli-get (lit fs) plan)
          (%awk-cli-get (lit assigns) plan)
          (%awk-cli-get (lit argv) plan))))))

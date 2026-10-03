# @weight 2

The CLI front's spec-able half: the pure argv parser, redirection and
file getline against real files, system(), and the exit status.  The
effectful whole -- x -l awk over pipes and files, -F/-v/-f, the dash
operand, FILENAME/FNR across files -- is exercised from a shell; this
file pins the pieces a spec can hold.

## the argv parser

### engine flags and the leading -- strip away

```awk
(write (awk-argv (list "x-bin" "--quiet" "--batch" "--" "-F:" "p" "f1")))
```
---
    ("-F:" "p" "f1")

### options split or joined, program, operands

```awk
(write (awk-parse-cli (list "-F" ":" "-v" "a=1" "p" "f1" "x=2")))
```
---
    ((fs . ":") (assigns ("a" . "1")) (progfiles) (prog . "p") (argv "f1" "x=2"))

### joined spellings

```awk
(write (awk-parse-cli (list "-F:" "-va=1" "p")))
```
---
    ((fs . ":") (assigns ("a" . "1")) (progfiles) (prog . "p") (argv))

### -f collects and wins over a program operand

```awk
(write (awk-parse-cli (list "-f" "a.awk" "-f" "b.awk" "f1")))
```
---
    ((fs) (assigns) (progfiles "a.awk" "b.awk") (prog) (argv "f1"))

### options stop at the first operand; a -F given twice keeps the last

```awk
(write (awk-parse-cli (list "-F" "a" "-F:" "p" "-v" "x=1")))
```
---
    ((fs . ":") (assigns) (progfiles) (prog . "p") (argv "-v" "x=1"))

### a line that does not run parses to nil: an option awk does not take, a -v that is not name=value

```awk
(write (list (awk-parse-cli (list "-Q" "p")) (awk-parse-cli (list "-v" "x" "p")) (awk-parse-cli (list "-F"))))
```
---
    (() () ())

## help and refusals

The options are one Opts declaration: busybox's awk help text, less the -E
spelling and the -e row for options this awk does not take.  `--help` prints
it on stdout, and 0; a refusal is musl getopt's line, then the usage text, on
stderr, and 1 -- as busybox's awk.  A bad -v, and no program at all, are the
usage text alone.

### the help text

```awk
(display (Opts usage %awk-options))
```
---
```output
Usage: awk [OPTIONS] [AWK_PROGRAM] [FILE]...

	-v VAR=VAL	Set variable
	-F SEP		Use SEP as field separator
	-f FILE		Read program from FILE
```

### --help is asked for first

```awk
(write (list (Opts help? %awk-options (list "--help")) (Opts help? %awk-options (list "p" "--help"))))
```
---
    (#t #f)

### the words: a letter, a long option (awk takes none, so it is the option -), a value option given nothing

```awk
(write (list (%awk-refusal "-Q") (%awk-refusal "--nope") (%awk-refusal "-F")))
```
---
    ("unrecognized option: Q" "unrecognized option: -" "option requires an argument: F")

## redirection and file getline

### print > and >> then getline < reads it back

```awk
(awk-run "BEGIN{f=\"/tmp/x-awk-spec-scratch.txt\"; print \"alpha\" > f; print \"beta\" >> f; close(f); while ((getline l < f) > 0) print \"got\", l}" "")
```
---
```output
got alpha
got beta
```

### the CLI runner reads files with FILENAME and FNR

```awk
(display (%awk-run-cli "{print FILENAME, FNR, NR}" () () (list "/tmp/x-awk-spec-scratch.txt")))
```
---
```output
/tmp/x-awk-spec-scratch.txt 1 1
/tmp/x-awk-spec-scratch.txt 2 2
0
```

### scratch cleanup

```awk
(do (file-unlink "/tmp/x-awk-spec-scratch.txt") (display "clean"))
```
---
    clean

### getline from a missing file answers -1

```awk
(awk-run "BEGIN{print (getline l < \"/tmp/x-awk-no-such-file-zz\")}" "")
```
---
    -1

## system and the exit status

### system answers the command's status

```awk
(awk-run "BEGIN{print system(\"true\"), system(\"false\")}" "")
```
---
    0 1

### exit's value is the run's status

```awk
(display (%awk-run-cli "BEGIN{exit 4}" () () ()))
```
---
    4

### -v assignments apply ahead of BEGIN

```awk
(display (%awk-run-cli "BEGIN{print x; exit}" () (list (pair "x" "7")) ()))
```
---
```output
7
0
```

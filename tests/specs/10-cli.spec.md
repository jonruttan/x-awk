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

# @weight 2

The pipe forms: "cmd" | getline reads a command's output as records;
print | "cmd" feeds a command's stdin, close() (or the run's end)
sending EOF and answering the command's exit status.  Expectations from
a real awk run -- including the one-true-awk behaviors POSIX leaves
looser: pipe getline does NOT count NR, and one command string is one
shared stream.

## command to getline

### a command's output, one record

```awk
(awk-run "BEGIN{\"echo hi\" | getline l; print l}" "")
```
---
    hi

### the bare form sets $0 and NF but never NR

```awk
(awk-run "BEGIN{\"echo q\" | getline; print NR, NF, $0}" "")
```
---
    0 1 q

### records stream through a while

```awk
(awk-run "BEGIN{while ((\"echo a; echo b\" | getline) > 0) n++; print n, $0}" "")
```
---
    2 b

### one command string is one stream

```awk
(awk-run "BEGIN{\"echo a; echo b\" | getline; \"echo a; echo b\" | getline; print $0, NR}" "")
```
---
    b 0

### a silent command is 0, not an error

```awk
(awk-run "BEGIN{print (\"true\" | getline x)}" "")
```
---
    0

## print to a command

### the child receives what print wrote; close answers its status

```awk
(awk-run "BEGIN{c=\"cat > /tmp/x-awk-spec-pipe.txt\"; print \"z\" | c; print close(c); while ((getline l < \"/tmp/x-awk-spec-pipe.txt\") > 0) print \"got\", l}" "")
```
---
```output
0
got z
```

### a child that exits without reading does not kill the run

SIGPIPE is ignored while an output pipe is open (restored at the run's
end); the write into a dead child fails instead of killing the process.

```awk
(awk-run "BEGIN{print \"x\" | \"exit 7\"; print \"alive\"}" "")
```
---
    alive

### close resets a command's getline stream

```awk
(awk-run "BEGIN{\"echo a; echo b\" | getline; close(\"echo a; echo b\"); \"echo a; echo b\" | getline; print $0}" "")
```
---
    a

### scratch cleanup

```awk
(do (file-unlink "/tmp/x-awk-spec-pipe.txt") (display "clean"))
```
---
    clean

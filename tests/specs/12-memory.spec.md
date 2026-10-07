# @weight 2

The record loop sweeps the heap between records (`%awk-sweep!` in
awk/eval.x).  These cases set the interval to 1, so every record ends in a
sweep, and check that what a program keeps across records survives one:
variables, arrays, compiled patterns, user functions, open output files,
the reader's unconsumed bytes.  The last case checks the point of the
sweep: the heap after many records is near where it started.

## state survives a sweep after every record

### variables, arrays, patterns and functions

```awk
(do (def mem-lines
      (fn (self i acc)
        (if (= i 0) (string-concat acc)
          (self (- i 1)
            (pair (string-append "row " (%awk-int->str i) " fox\n") acc)))))
    (set! %awk-sweep-every 1)
    (awk-run "function tw(x) { return x * 2 } /fox/ { n++; a[$2] = tw($2); s = s \"\" ($2 % 7) } END { print n, length(a), a[13], a[60], length(s), NR, $0 }"
      (mem-lines 60 ()))
    (set! %awk-sweep-every 16)
    ())
```
---
    60 60 26 120 60 60 row 60 fox

### an output file stays open across sweeps

```awk
(do (set! %awk-sweep-every 1)
    (awk-run "{ print $1 > \"/tmp/x-awk-spec-sweep.txt\" } END { close(\"/tmp/x-awk-spec-sweep.txt\"); while ((getline l < \"/tmp/x-awk-spec-sweep.txt\") > 0) k = k l; print k }"
      "a\nb\nc\nd\ne\n")
    (file-unlink "/tmp/x-awk-spec-sweep.txt")
    (set! %awk-sweep-every 16)
    ())
```
---
    abcde

### records split across small reads

```awk
(do (set! %awk-sweep-every 1)
    (set! %awk-read-size 4)
    (awk-run "{ t = t $2 } END { print NR, t }" "x alpha\ny beta\nz gamma\n")
    (set! %awk-read-size 65536)
    (set! %awk-sweep-every 16)
    ())
```
---
    3 alphabetagamma

## the heap stays near its floor

### 300 records leave the heap where it started

Without the sweep each of these records leaves tens of thousands of
objects behind; 300 of them would grow the heap by millions.

```awk
(do (def mem-lines
      (fn (self i acc)
        (if (= i 0) (string-concat acc)
          (self (- i 1)
            (pair (string-append "line " (%awk-int->str i)
                    " the quick brown fox jumps over the lazy dog\n") acc)))))
    (def mem-in (mem-lines 300 ()))
    (set! %awk-sweep-every 2)
    (heap-collect)
    (def mem-h0 (heap-count))
    (awk-run "{ n += NF } END { print n }" mem-in)
    (def mem-grew (- (heap-count) mem-h0))
    (set! %awk-sweep-every 16)
    (display (if (< mem-grew 1000000) "flat" mem-grew)))
```
---
```output
3300
flat
```

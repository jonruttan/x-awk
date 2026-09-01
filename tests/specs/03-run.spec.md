# @weight 3

End to end: `(awk-run PROGRAM INPUT)` -- the pure core.  Every expected
output here was taken from a real awk run (macOS one-true-awk) on the same
program and input: the oracle, not our own expectations.

## BEGIN and END

### BEGIN runs before any record

```awk
(awk-run "BEGIN{print \"hi\"}" "")
```
---
    hi

### END sees the final NR

```awk
(awk-run "END{print NR}" "a\nb\nc\n")
```
---
    3

## records and fields

### fields reverse

```awk
(awk-run "{print $2, $1}" "a b\nc d\n")
```
---
```output
b a
d c
```

### NR and NF count

```awk
(awk-run "{print NR, NF}" "a b\nc\n")
```
---
```output
1 2
2 1
```

### FS set in BEGIN splits the records

```awk
(awk-run "BEGIN{FS=\",\"}{print $2}" "a,b\n")
```
---
    b

### OFS joins the print list

```awk
(awk-run "BEGIN{OFS=\"-\"}{print $1,$2}" "a b\n")
```
---
    a-b

## patterns

### an ERE pattern selects records

```awk
(awk-run "/b/{print}" "ab\ncd\n")
```
---
    ab

### a match against one field

```awk
(awk-run "$1 ~ /^c/ {print $2}" "ca x\nda y\n")
```
---
    x

### strnum fields compare numerically

```awk
(awk-run "$1 < $2 {print}" "10 9\n9 10\n")
```
---
    9 10

### string constants compare as strings

```awk
(awk-run "BEGIN{print (\"10\" < \"9\")}" "")
```
---
    1

## arithmetic

### exact quarters

```awk
(awk-run "BEGIN{print 1/4+0.25}" "")
```
---
    0.5

### a third renders as %.6g

```awk
(awk-run "BEGIN{print 1/3}" "")
```
---
    0.333333

### power, and a negative exponent

```awk
(awk-run "BEGIN{print 2^10, 2^-2}" "")
```
---
    1024 0.25

### modulo

```awk
(awk-run "BEGIN{print 7%3}" "")
```
---
    1

### int truncates toward zero

```awk
(awk-run "BEGIN{print length(\"hello\"), int(3.9), int(-3.9)}" "")
```
---
    5 3 -3

## strings

### concatenation is juxtaposition, addition binds tighter

```awk
(awk-run "BEGIN{print \"a\" 1+1}" "")
```
---
    a2

### substr, index, length

```awk
(awk-run "BEGIN{print substr(\"hello\",2,3), index(\"hello\",\"ll\"), length(\"hello\")}" "")
```
---
    ell 3 5

## control flow

### while

```awk
(awk-run "BEGIN{i=0;while(i<3){print i;i++}}" "")
```
---
```output
0
1
2
```

### for

```awk
(awk-run "BEGIN{for(i=0;i<3;i++)print i}" "")
```
---
```output
0
1
2
```

### next skips the remaining rules for the record

```awk
(awk-run "{if(NR==1) next; print}" "a\nb\n")
```
---
    b

### exit stops records but still runs END

```awk
(awk-run "{print; exit} END{print \"end\"}" "a\nb\n")
```
---
```output
a
end
```

### the ternary

```awk
(awk-run "BEGIN{x=5; print (x>3?\"y\":\"n\")}" "")
```
---
    y

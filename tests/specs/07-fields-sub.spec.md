# @weight 2

Field assignment and sub/gsub.  Assigning any $i rebuilds $0 by joining
the fields with OFS at that moment; assigning $0 re-splits per FS; NF is
live in both directions.  sub/gsub write through the same l-value door,
so a field target rebuilds $0 exactly as a plain assignment would.  All
expectations from a real awk run.

## field assignment

### a field replaces and $0 follows

```awk
(awk-run "{$2=\"X\"; print}" "a b c\n")
```
---
    a X c

### the $1=$1 idiom re-joins with OFS

```awk
(awk-run "BEGIN{OFS=\"-\"}{$1=$1; print}" "a b c\n")
```
---
    a-b-c

### assigning past NF fills the gap with empty fields

```awk
(awk-run "{$5=\"e\"; print NF; print $0 \"|\"}" "a b\n")
```
---
```output
5
a b   e|
```

### assigning $0 re-splits

```awk
(awk-run "{$0=\"x y\"; print $2, NF}" "ignored\n")
```
---
    y 2

### NF truncates

```awk
(awk-run "{NF=2; print $0 \"|\"; print NF}" "a b c\n")
```
---
```output
a b|
2
```

### NF extends

```awk
(awk-run "{NF=4; print $0 \"|\"}" "a b\n")
```
---
    a b  |

## sub and gsub

### sub replaces once and reports

```awk
(awk-run "BEGIN{s=\"aaa\"; n=sub(/a/,\"b\",s); print n, s}" "")
```
---
    1 baa

### gsub replaces all and counts

```awk
(awk-run "BEGIN{s=\"aaa\"; n=gsub(/a/,\"b\",s); print n, s}" "")
```
---
    3 bbb

### no match answers zero and leaves the target alone

```awk
(awk-run "BEGIN{s=\"c\"; print sub(/a/,\"b\",s), s}" "")
```
---
    0 c

### & is the matched text

```awk
(awk-run "BEGIN{s=\"ab\"; gsub(/b/,\"[&]\",s); print s}" "")
```
---
    a[b]

### doubled & doubles the match

```awk
(awk-run "BEGIN{s=\"a\"; gsub(/a/,\"&&\",s); print s}" "")
```
---
    aa

### backslash-& is a literal ampersand

```awk
(awk-run "BEGIN{s=\"b\"; gsub(/b/,\"\\\\&\",s); print s}" "")
```
---
    &

### the target defaults to $0

```awk
(awk-run "{gsub(/a/,\"x\"); print}" "aba\n")
```
---
    xbx

### a field target rebuilds $0 with OFS

```awk
(awk-run "BEGIN{OFS=\"-\"}{gsub(/a/,\"x\",$2); print}" "za ab\n")
```
---
    za-xb

### sub on a field, record and field both updated

```awk
(awk-run "{sub(/b/,\"X\",$2); print; print $2}" "ab bb\n")
```
---
```output
ab Xb
Xb
```

### empty matches replace between every character

```awk
(awk-run "BEGIN{s=\"abc\"; n=gsub(/x*/,\"-\",s); print n, s}" "")
```
---
    4 -a-b-c-

### a dynamic pattern compiles from its string

```awk
(awk-run "BEGIN{s=\"aa\"; r=\"a\"; gsub(r,\"b\",s); print s}" "")
```
---
    bb

### deleting by empty replacement

```awk
(awk-run "BEGIN{s=\"aXa\"; gsub(/a/,\"\",s); print s \"|\"}" "")
```
---
    X|

# @weight 2

Arrays and split().  String-keyed associative arrays with POSIX's paired
rules: REFERENCING an element creates it, `in` tests without creating,
subscripts stringify (through the output formatter) and multi-subscripts
join with SUBSEP.  Every expectation here came from a real awk run.

## elements

### store and fetch

```awk
(awk-run "BEGIN{a[\"x\"]=1; a[\"y\"]=2; print a[\"x\"], a[\"y\"]}" "")
```
---
    1 2

### auto-create under ++

```awk
(awk-run "BEGIN{a[1]++; a[1]++; print a[1]}" "")
```
---
    2

### a numeric subscript is the same key as its string

```awk
(awk-run "BEGIN{a[1]=\"one\"; print a[\"1\"]}" "")
```
---
    one

### compound assignment and increment on elements

```awk
(awk-run "BEGIN{a[\"k\"]=5; a[\"k\"]+=2; a[\"k\"]++; print a[\"k\"]}" "")
```
---
    8

### a multi-subscript joins with SUBSEP into one key

```awk
(awk-run "BEGIN{a[1,2]=3; print a[1,2]}" "")
```
---
    3

## in, and the two creation rules

### in answers membership

```awk
(awk-run "BEGIN{a[\"x\"]=1; print (\"x\" in a), (\"y\" in a)}" "")
```
---
    1 0

### in does not create

```awk
(awk-run "BEGIN{if (\"y\" in a) x=1; print length(a)}" "")
```
---
    0

### referencing does create

```awk
(awk-run "BEGIN{x=a[\"k\"]; print length(a)}" "")
```
---
    1

## for-in

### walks every key

```awk
(awk-run "BEGIN{a[\"b\"]=1;a[\"c\"]=2; n=0; for (k in a) n++; print n}" "")
```
---
    2

### the key is input-shaped: numeric text compares numerically

```awk
(awk-run "BEGIN{a[10]=1; for (k in a) print (k==10)}" "")
```
---
    1

## delete

### one element

```awk
(awk-run "BEGIN{a[1]=1;a[2]=2; delete a[1]; print (1 in a), (2 in a)}" "")
```
---
    0 1

### the whole array

```awk
(awk-run "BEGIN{a[1]=1; delete a; print length(a)}" "")
```
---
    0

## split

### an explicit separator

```awk
(awk-run "BEGIN{n=split(\"a:b:c\", arr, \":\"); print n, arr[1], arr[3]}" "")
```
---
    3 a c

### FS by default

```awk
(awk-run "BEGIN{n=split(\"x y z\", arr); print n, arr[2]}" "")
```
---
    3 y

### an ERE separator

```awk
(awk-run "BEGIN{n=split(\"a1b22c\", arr, /[0-9]+/); print n, arr[3]}" "")
```
---
    3 c

### elements are input-shaped: numeric text compares numerically

```awk
(awk-run "BEGIN{split(\"10 9\", arr); print (arr[1] > arr[2])}" "")
```
---
    1

### an empty string has no fields

```awk
(awk-run "BEGIN{n=split(\"\", arr); print n, length(arr)}" "")
```
---
    0 0

## in anger

### the word-count shape

```awk
(awk-run "{for (i=1; i<=NF; i++) sum[$i]++} END{print sum[\"a\"]}" "a b\na c\n")
```
---
    2

# @weight 2

getline (the main-input forms), RS, and user functions.  The record
stream materializes on first touch, so RS set in BEGIN governs the split
and getline works from BEGIN.  All expectations from a real awk run.

## RS

### a custom separator

```awk
(awk-run "BEGIN{RS=\";\"}{print NR, $0}" "a;b;c")
```
---
```output
1 a
2 b
3 c
```

### a newline inside a record is just a blank

```awk
(awk-run "BEGIN{RS=\";\"}{print NR, $1, NF}" "a;b\nc;")
```
---
```output
1 a 1
2 b 2
```

### paragraph mode: blank lines separate, newline splits fields

```awk
(awk-run "BEGIN{RS=\"\"}{print NR, NF, $2}" "a b\nc\n\nd\n")
```
---
```output
1 3 b
2 1 
```

### paragraph mode skips leading and trailing blank lines

```awk
(awk-run "BEGIN{RS=\"\"}{print NR, $3}" "\n\nx y\nz\n\nw\n")
```
---
```output
1 z
2 
```

## getline

### bare getline swaps the record mid-rules

```awk
(awk-run "NR==1{getline; print \"got\", $0} {print \"rule\", NR, $1}" "a\nb\nc\n")
```
---
```output
got b
rule 2 b
rule 3 c
```

### getline var reads the text without touching $0

```awk
(awk-run "{r=getline line; print $0, r, line}" "a\nb\nc\nd\n")
```
---
```output
a 1 b
c 1 d
```

### getline answers 0 at end of input

```awk
(awk-run "{r=getline; print r, $0}" "a\nb\n")
```
---
    1 b

## user functions

### define and call

```awk
(awk-run "function add(a,b){return a+b} BEGIN{print add(2,3)}" "")
```
---
    5

### an extra parameter is a local, restored after the call

```awk
(awk-run "function f(a, b){b=9; return a} BEGIN{b=1; f(2); print b}" "")
```
---
    1

### a scalar argument passes by value

```awk
(awk-run "function f(x){x=99} BEGIN{y=5; f(y); print y}" "")
```
---
    5

### an array argument passes by reference

```awk
(awk-run "function fill(arr){arr[\"k\"]=7} BEGIN{a[\"x\"]=1; fill(a); print a[\"k\"], length(a)}" "")
```
---
    7 2

### recursion

```awk
(awk-run "function fact(n){if(n<=1) return 1; return n*fact(n-1)} BEGIN{print fact(5)}" "")
```
---
    120

### a bare return answers uninit

```awk
(awk-run "function g(){return} BEGIN{print g() \"|\"}" "")
```
---
    |

### definition order does not matter

```awk
(awk-run "{print dbl($1)} function dbl(x){return x*2}" "3\n5\n")
```
---
```output
6
10
```

### calling an undefined function is a loud error

```awk
(awk-run "BEGIN{print nosuch(1)}" "")
```
---
    Error: #<err:awk awk: calling undefined function nosuch>

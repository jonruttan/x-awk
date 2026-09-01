# @weight 2

toupper, tolower, match, and the math set.  The transcendentals ride the
platform's libm floats, converted back to exact rationals at the boundary
(14 significant digits, comfortably past %.6g), so floats never enter the
value model.  rand is the platform's deterministic xorshift behind the
srand seed protocol.  Deterministic expectations from a real awk run.

## case mapping

### toupper and tolower, non-letters untouched

```awk
(awk-run "BEGIN{print toupper(\"aB-c\"), tolower(\"Dz9\")}" "")
```
---
    AB-C dz9

## match

### a hit sets RSTART and RLENGTH and answers RSTART

```awk
(awk-run "BEGIN{n=match(\"abcdef\", /cd/); print n, RSTART, RLENGTH}" "")
```
---
    3 3 2

### a miss answers 0 with RLENGTH -1

```awk
(awk-run "BEGIN{print match(\"ab\", /x/), RSTART, RLENGTH}" "")
```
---
    0 0 -1

### a quantified pattern reports its true extent

```awk
(awk-run "BEGIN{x=match(\"aaa bbb\", /b+/); print RSTART, RLENGTH}" "")
```
---
    5 3

## the math set

### sqrt through %.6g and an exact square

```awk
(awk-run "BEGIN{print sqrt(2), sqrt(9)}" "")
```
---
    1.41421 3

### sin and cos at zero come back exact

```awk
(awk-run "BEGIN{print sin(0), cos(0)}" "")
```
---
    0 1

### atan2 finds pi

```awk
(awk-run "BEGIN{printf \"%.5f\\n\", atan2(0,-1)}" "")
```
---
    3.14159

### exp and its log round-trip

```awk
(awk-run "BEGIN{print exp(1), log(exp(2))}" "")
```
---
    2.71828 2

### the boundary feeds printf precision

```awk
(awk-run "BEGIN{printf \"%.3f|%.6f|\\n\", sqrt(2), sin(1)}" "")
```
---
    1.414|0.841471|

## rand and srand

### rand stays in the unit interval

```awk
(awk-run "BEGIN{srand(1); r=rand(); print ((r>=0) && (r<1))}" "")
```
---
    1

### the same seed replays the same stream

```awk
(awk-run "BEGIN{srand(7); a=rand(); srand(7); b=rand(); print (a==b)}" "")
```
---
    1

### srand answers the previous seed

```awk
(awk-run "BEGIN{srand(3); x=srand(5); print x}" "")
```
---
    3

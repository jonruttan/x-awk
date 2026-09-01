# @weight 2

printf, sprintf, and the format engine -- which also owns OFMT and
CONVFMT, so every number the bundle renders comes from one place.  All
expectations from a real awk run, except where a case says otherwise.

## integers

### width, left-justify, zero-pad

```awk
(awk-run "BEGIN{printf \"%d|%5d|%-5d|%05d|\\n\", 42, 42, 42, 42}" "")
```
---
    42|   42|42   |00042|

### the sign flags

```awk
(awk-run "BEGIN{printf \"%+d|% d|\\n\", 5, 5}" "")
```
---
    +5| 5|

### hex, octal, unsigned

```awk
(awk-run "BEGIN{printf \"%x %X %o %u\\n\", 255, 255, 8, 7}" "")
```
---
    ff FF 10 7

## characters and strings

### %c from a code and from a string

```awk
(awk-run "BEGIN{printf \"%c%c|\\n\", 65, \"BC\"}" "")
```
---
    AB|

### %s width and justification

```awk
(awk-run "BEGIN{printf \"%s|%10s|%-10s|\\n\", \"a\", \"b\", \"c\"}" "")
```
---
    a|         b|c         |

### %s precision truncates

```awk
(awk-run "BEGIN{printf \"%.3s|\\n\", \"hello\"}" "")
```
---
    hel|

## floating forms, exactly

### %f default and given precision

```awk
(awk-run "BEGIN{printf \"%f|%.2f|%8.2f|\\n\", 3.14159, 3.14159, 3.14159}" "")
```
---
    3.141590|3.14|    3.14|

### %e both ways around one

```awk
(awk-run "BEGIN{printf \"%e|%.2e|\\n\", 31415.9, 0.000123}" "")
```
---
    3.141590e+04|1.23e-04|

### %g picks its form and strips

```awk
(awk-run "BEGIN{printf \"%g|%g|%g|%g|%g|%g|\\n\", 0.0001, 0.00001, 100000, 1000000, 0.5, 3}" "")
```
---
    0.0001|1e-05|100000|1e+06|0.5|3|

### the uppercase twins

```awk
(awk-run "BEGIN{printf \"%G|%E|\\n\", 0.00001, 12345.6}" "")
```
---
    1E-05|1.234560E+04|

### width and precision from *

```awk
(awk-run "BEGIN{printf \"%*d|%.*f|\\n\", 5, 42, 2, 3.14159}" "")
```
---
       42|3.14|

### mixed width, precision, justification

```awk
(awk-run "BEGIN{printf \"%5.2f|%-8.3e|\\n\", 3.14159, 12345.678}" "")
```
---
     3.14|1.235e+04|

## the engine behind print

### print reaches e-notation through OFMT's %.6g

```awk
(awk-run "BEGIN{print 0.0000001}" "")
```
---
    1e-07

### OFMT drives print

```awk
(awk-run "BEGIN{OFMT=\"%.2f\"; print 3.14159}" "")
```
---
    3.14

### CONVFMT drives conversion

```awk
(awk-run "BEGIN{CONVFMT=\"%.2f\"; x=3.14159; y=x \"\"; print y}" "")
```
---
    3.14

## sprintf

### answers a string

```awk
(awk-run "BEGIN{s=sprintf(\"%04d\", 7); print s}" "")
```
---
    0007

## edges

### a literal percent

```awk
(awk-run "BEGIN{printf \"%%d|\\n\"}" "")
```
---
    %d|

### not enough arguments is an error, as the one-true-awk has it

```awk
(awk-run "BEGIN{printf \"%d %d\\n\", 7}" "")
```
---
    Error: #<err:awk awk: printf: not enough arguments>

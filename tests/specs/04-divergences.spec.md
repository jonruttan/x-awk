# @weight 1

Recorded divergences from C awk -- pending, per the crafting doc's rule
that a divergence lives as a spec, not a comment.  Each heading states the
gap; a case graduates (gains its `---` and expected output) when the
behavior is settled or built.

## exact arithmetic

### float roundoff does not occur: 0.1+0.2==0.3 answers 1 here, 0 in C awk

```awk
(awk-run "BEGIN{print (0.1+0.2==0.3)}" "")
```

The core is exact-rational; C awk is IEEE doubles.  This bundle answers 1
(the mathematically true reading), one-true-awk answers 0.  Settle which
contract x-awk ships before graduating this.

## rounding

### %.0f of 2.5: half-up here, half-even on C doubles

```awk
(awk-run "BEGIN{printf \"%.0f\\n\", 2.5}" "")
```

The exact engine rounds half-up (3); C awk's doubles round half-even (2).
POSIX mandates neither.  Settle the contract before graduating.

### %x of a negative: sign-prefixed here, unsigned-wrapped in C

```awk
(awk-run "BEGIN{printf \"%x\\n\", -1}" "")
```

C awk casts through unsigned long (ffffffffffffffff); the exact engine
has no word size to wrap at and prints -1.

### math results tail to zeros past ten significant digits

```awk
(awk-run "BEGIN{printf \"%.12f\\n\", sqrt(2)}" "")
```

C awk prints 1.414213562373; the float boundary caps its rationals at
ten significant digits (1.414213562000).  The cap was born as a fence
against a tower defect (rational cross products wrapping past 2^63),
SINCE FIXED in x-lang; it stays as an economy -- native-int formatter
intermediates, no bigint churn -- see the %awk-float->rat comment.
Lift it the day a spec wants the extra digits.

## leftmost-longest

### POSIX ERE wants the longest match at the leftmost position

```awk
(awk-run "BEGIN{s=\"aaa\"; if (s ~ /a|aa/) print \"m\"}" "")
```

lib/x/type/regex.x is a backtracking leftmost-FIRST engine (PCRE-style);
POSIX awk requires leftmost-LONGEST.  Matching (not extraction) rarely
differs; sub/gsub extraction will, once built.

## close of a failing output pipe

### close answers the command's exit status, not one-true-awk's 0

```awk
(awk-run "BEGIN{cmd=\"read x; exit 7\"; print \"x\" | cmd; print close(cmd)}" "")
```
---
    7

POSIX says close of a print pipe answers the command's exit status, and
gawk agrees (7); one-true-awk 20200816 answers 0 no matter what the
child exited with.  This bundle follows POSIX -- the status is the whole
point of checking close.

## not built yet, loudly

### exit from inside a function

```awk
(awk-run "function f(){exit 1} BEGIN{f()}" "")
```

POSIX allows it (next it forbids); here every control escaping a
function raises.  Thread an exit flag when someone needs it.

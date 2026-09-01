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

## leftmost-longest

### POSIX ERE wants the longest match at the leftmost position

```awk
(awk-run "BEGIN{s=\"aaa\"; if (s ~ /a|aa/) print \"m\"}" "")
```

lib/x/type/regex.x is a backtracking leftmost-FIRST engine (PCRE-style);
POSIX awk requires leftmost-LONGEST.  Matching (not extraction) rarely
differs; sub/gsub extraction will, once built.

## not built yet, loudly

### getline, redirection, system, command-line files

```awk
(awk-run "{print > \"file\"}" "a\n")
```

### user functions

```awk
(awk-run "function f(x){return x+1} BEGIN{print f(1)}" "")
```

### toupper, tolower, match, and the math functions

```awk
(awk-run "BEGIN{print toupper(\"ab\")}" "")
```

### RS: custom record separators

```awk
(awk-run "BEGIN{RS=\";\"}{print NR, $0}" "a;b")
```

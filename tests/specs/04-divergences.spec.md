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

## %.6g e-notation

### very large and very small non-integral values should shift to e-notation

```awk
(awk-run "BEGIN{print 0.0000001}" "")
```

C awk prints 1e-07 (%.6g shifts when the exponent leaves [-4, 6));
%awk-num->str renders plain decimals only.

## leftmost-longest

### POSIX ERE wants the longest match at the leftmost position

```awk
(awk-run "BEGIN{s=\"aaa\"; if (s ~ /a|aa/) print \"m\"}" "")
```

lib/x/type/regex.x is a backtracking leftmost-FIRST engine (PCRE-style);
POSIX awk requires leftmost-LONGEST.  Matching (not extraction) rarely
differs; sub/gsub extraction will, once built.

## not built yet, loudly

### printf and sprintf

```awk
(awk-run "BEGIN{printf \"%d\\n\", 42}" "")
```

### arrays, split, for-in, delete

```awk
(awk-run "BEGIN{a[1]=2; print a[1]}" "")
```

### field assignment rebuilds the record

```awk
(awk-run "{$1=\"x\"; print}" "a b\n")
```

### getline, redirection, system, command-line files

```awk
(awk-run "{print > \"file\"}" "a\n")
```

### user functions

```awk
(awk-run "function f(x){return x+1} BEGIN{print f(1)}" "")
```

### sub, gsub, sprintf, toupper, tolower, sin and friends

```awk
(awk-run "BEGIN{s=\"aa\"; gsub(/a/,\"b\",s); print s}" "")
```

### RS: custom record separators

```awk
(awk-run "BEGIN{RS=\";\"}{print NR, $0}" "a;b")
```

# The numeric gap, priced

`x -l awk` has no fractional arithmetic.  Not "an edge case in division" --
every value with a fraction in it truncates to an integer, because the
bundle declares dialect `he` (helium) and `awk/prims.x` imports
`x/num/float` alone.  Helium's core arithmetic is integer arithmetic; the
rationals awk's value model is written against are not there.

The suite does not see it.  `tests/lib/harness.gen.x` boots `x-base.x`,
whose tower is compiled in, so the specs run against arithmetic the
shipped lang does not have.  That is why this file exists: the gap was
found on 2026-09-05 by a harness on bare `x-core.x` (19 failures), and
`tests/gen-harness.sh` has carried a note about it since.

## What is actually broken

`BEGIN` blocks, one line each, against `/usr/bin/awk` (one-true-awk
20200816) on the same program.  Measured 2026-09-06, x-lang v0.12.0.

| program | `x -l awk` | one-true-awk |
|---|---|---|
| `print 1/4, 10/4, 3/2*2` | `0 2 2` | `0.25 2.5 3` |
| `print 0.25, 3.14, 1.5+1.5` | `0 3 2` | `0.25 3.14 3` |
| `print "3.14"+0, "0.5"*2` | `3 0` | `3.14 1` |
| `print exp(1), log(2.718281828)` | `2 0` | `2.71828 1` |
| `print sqrt(2), 2^0.5` | `1 1` | `1.41421 1.41421` |
| `print sin(1), cos(1), atan2(1,1)` | `0 0 0` | `0.841471 0.540302 0.785398` |
| `printf "%.4f %.2f %g", 1/3, 2.5, 0.0001` | `0.0000 2.00 0` | `0.3333 2.50 0.0001` |
| `print (0.5 > 0.25), (1/3 < 0.34)` | `0 0` | `1 1` |
| `print 3.14159265` | `3` | `3.14159` |
| `x["k"]=1/8; print x["k"]` | `0` | `0.125` |

Float literals, string-to-number conversion, every math builtin, `printf`'s
float conversions, comparisons and array values are all affected.  The
lexer's exact reading is intact -- `0.25` becomes the rational 1/4 as
designed -- but nothing downstream can hold it, so it lands as 0.

## The options, measured

Four ways to give the lang the arithmetic it is written against.  Same
machine, x-lang v0.12.0 built from a checkout, and (for the image
columns) x-lang main at 6c0ab5c5, which is where `x --image` and a lang
booting from its own state image live.  `x -l awk` on a one-line program
is the boot measure; the arithmetic measure is a 10,000-iteration integer
loop, booted from an image so the boot is not in it.

| | boot, source | boot, image | image | int loop | arithmetic |
|---|--:|--:|--:|--:|---|
| as shipped: `he` + float | 6.7s | 0.50s | 7.04 MB | 7.4s | wrong, silently |
| `he` + `x/num/tower`, last line of `awk/base.x` | 13.3s | 0.52s | 8.10 MB | 9.5s | correct |
| `he` + `x/num/tower`, in `awk/prims.x` | 26.1s | -- | -- | -- | correct |
| `he` + `x/num/rational` alone | 9.0s | -- | -- | -- | worse than shipped |
| dialect `xe` | 9.2s | 0.94s | 9.20 MB | 9.7s | correct |
| dialect `rn` | 9.0s | 0.92s | 9.25 MB | 9.5s | correct |

**Placement is worth 13 seconds.**  The tower hooks number analysers into
the reader, and every byte read after the import pays them.  Imported in
`awk/prims.x` it is read *before* `lex.x`, `parse.x` and `eval.x`, so
awk's own 130K of source comes through the analysers: 26.1s.  Imported on
the last line of `awk/base.x`, after the includes, only the user's program
text pays: 13.3s.  This is the same effect the spec harness hit from the
other side (26s and then dead, every file, when the harness imported the
tower before `awk/base`).

**Rational alone is not a cheap tower.**  It costs almost nothing to load
(+0.2s) and `rational.x` does register its own conversion into float, but
awk's seams break on it: `print 1/4`, `print 0.25`, `print sqrt(2)` and
`x ""` all raise `Str8 append: not a string`, a comparison raises
`Str8 length: not a string`, and `int(1/4*8)` answers 0 where 2 is right.
The mixed-type policy those seams need is exactly what `x/num/tower`
exists to hold, and hand-writing it in the bundle would vendor platform
policy the bundle deliberately does not vendor.

**A heavier dialect is real, and it is not free either.**  `xe` and `rn`
carry the tower compiled, so they boot from source faster than helium
loading it interpreted (9.2s against 13.3s).  From an image, which is how
an installed lang boots, they are the slower option: 0.94s against 0.52s,
on an image a megabyte larger.  They also re-open the dialect row that
`lang.xon` argues, at length, should not change per release.

## What the fix costs, stated plainly

Taking the tower on the last line of `awk/base.x`:

- **From a state image, nothing measurable.**  0.52s against 0.50s, which
  is inside the noise of three runs.  The image is 1.06 MB larger (+15%),
  and `make install`'s image write goes from 16.1s to 23.3s on a cold asm
  byte cache -- paid once, by the installer.
- **From source, +6.6s per invocation.**  This is the number that matters
  today: `x --image` does not exist in v0.12.0, the release `lang.xon`
  requires, so every `x -l awk` on it boots from source.  The bundle's
  `make install` already calls `x --image -l awk || true` for the wrapper
  that does have it, so the bundle is betting on the next release either
  way.
- **+28% on arithmetic-heavy programs.**  The integer loop goes 7.4s to
  9.5s.  This is not the tower's overhead as such: `xe` and `rn`, with the
  tower compiled, cost the same (9.7s and 9.5s).  It is the price of
  values that are rationals rather than machine integers, and every
  correct option pays it.
- **Nothing on the rest.**  A string-and-regex loop measures the same
  either way, and the spec suite is unchanged: 167 tests, 0 failed, 32s
  cold with the image write, because the harness was already on a tower.

## What it does not fix

`2^0.5` raises `awk: fractional exponents are not built yet (exact core)`
from `awk/eval.x`'s `pow` branch, which refuses any exponent with a
fraction.  Today, without the tower, the same program answers `1`,
because the exponent truncates to 0 before that check ever sees it.  So
closing the numeric gap turns one silently wrong answer into a loud
refusal -- an improvement, and a visible behaviour change.  The
divergence is already recorded in
`tests/specs/04-divergences.spec.md` under "not built yet, loudly".
`float-exp` and `float-log` are both in the prims list, so the exponent
itself is a small follow-on in `eval.x` once someone wants it.

## The recommendation

Import `x/num/tower` on the last line of `awk/base.x`, when the release
`lang.xon` requires is one whose `x -l awk` boots from a state image.
On that release the correctness is free at startup and the only standing
cost is the 28% on arithmetic, which no correct option avoids.  Doing it
before then trades a wrong answer for a doubled startup on every
invocation, which is a worse deal than it sounds: the wrong answers are
silent, but they are also, today, in every division a user writes.

# x-awk

POSIX awk on x-lang: pattern-action rules over records and fields, written
in x.  Part of the self-hosting arc -- awk is the heaviest external tool in
x-lang's own build closure after the regex trio (see x-lang's
`docs/bootstrap-closure.md`), and this bundle is the step that absorbs it.

Status: pre-release.  The core runs: BEGIN/END and pattern-action rules,
fields and NR/NF/FS/OFS/ORS, exact-rational arithmetic with awk's %.6g
output formatting, ERE patterns and `~`/`!~` (on `lib/x/type/regex.x`,
compiled at parse time), strnum comparison semantics, `print`, control flow
(`if`/`else`, `while`, `do`, `for`, `next`, `exit`, `break`, `continue`),
`length`/`substr`/`index`/`int`; arrays: string-keyed with POSIX's paired
creation rules (referencing creates, `in` does not), `for (k in a)`,
`delete`, multi-subscripts through SUBSEP, and `split()` with string, FS,
or ERE separators; `printf`/`sprintf`: the full conversion set
(d i o x X u c s f e E g G %%) with flags, width, precision and `*`, every
digit from exact integer arithmetic, with OFMT and CONVFMT wired through
the same engine; field assignment with the POSIX rebuild rules ($i and NF
rebuild $0 through OFS, $0 re-splits per FS); and `sub`/`gsub` with &
expansion, writing through the same l-value door as assignment;
`toupper`/`tolower`; `match` with RSTART/RLENGTH; the math set (sin, cos,
atan2, exp, log, sqrt) on the platform's libm floats, converted back to
rationals at the boundary so floats never enter the value model; and
`rand`/`srand` on the platform's deterministic xorshift.  The recorded
gaps -- getline, redirection, user functions, RS -- live as pending specs
in `tests/specs/04-divergences.spec.md`, not as promises.

Paired with x-lang v0.9.0 (`lang.xon` is the checkable row).

## Try it

    make install        # into the x on PATH
    x -l awk            # the awk core over an x REPL

The pure core is `(awk-run PROGRAM-TEXT INPUT-TEXT)`: program in, input in,
print output to stdout.  A real CLI front (`awk 'prog' file...`) arrives
with getline and ARGV.

## Tests

    make test           # the suite, loud on any failure
    make check          # judged against tests/contract/known-failures.txt

Every end-to-end expectation in `tests/specs/03-run.spec.md` was taken from
a real awk run on the same program and input -- the oracle, not our own
expectations.

## Layout

    lang.xon          what this bundle IS (lang, dialect, pairing, entry)
    run.x             the entry: imports awk/base, wires the seam globals
    awk/prims.x       the platform layer, one file
    awk/lex.x         program text -> tokens (a string scanner; see base.x)
    awk/parse.x       tokens -> AST, grammar only
    awk/eval.x        the AST's meaning: values, records, the run loop
    awk/fmt.x         the printf engine; OFMT/CONVFMT route through it
    awk/printer.x     the lang's own write
    tests/            markdown specs + the platform's runner, vendored nowhere

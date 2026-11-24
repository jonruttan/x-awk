# x-awk card

## Run

```sh
x -l awk 'PROGRAM' FILE...
x -l awk -- -F: -v n=3 -f PROGRAM-FILE FILE...
echo 'a b' | x -l awk '{ print $2 }' -> b
```

| Operand      | Meaning                                                |
|--------------|--------------------------------------------------------|
| `--`         | ends x's own options; awk's options follow it          |
| `-F SEP`     | the field separator, a string or a regular expression  |
| `-v NAME=V`  | assign a variable before `BEGIN` runs                  |
| `-f FILE`    | read the program from FILE; may be given more than once |
| `NAME=V`     | among the files: assign when the reading gets there    |
| `-`          | among the files: standard input; so is naming no file  |

## Program

### Shape

```input
alice 30 nyc
bob 25 sf
carol 35 nyc
```

```awk
BEGIN    { n = 0 }              # once, before any input
$2 > 28  { n++ }                # each record the pattern is true for
/^b/                            # a pattern alone: print the record
         { last = $1 }          # an action alone: every record
END      { print n, last }      # once, after the last record
# -> bob 25 sf
# -> 2 carol
```

### Patterns

| Pattern           | The records it selects                           |
|-------------------|--------------------------------------------------|
| `/re/`            | those the regular expression matches             |
| `$2 ~ /re/`       | those whose field 2 matches; `!~` for no match   |
| `$2 > 28`         | those the expression is true for                 |
| `a && b`, `a \|\| b`, `!a` | and, or, not                            |
| `/from/, /to/`    | from a match of the first through a match of the second |
| `BEGIN`, `END`    | none: before the input, and after it             |

## Variables

### Built in

| Name       | Meaning                                              |
|------------|------------------------------------------------------|
| `$0`       | the record                                           |
| `$1` `$2`  | its fields; `$NF` is the last, `$(NF-1)` the one before |
| `NF`       | how many fields this record has                      |
| `NR`       | how many records have been read                      |
| `FNR`      | the same, counted within the current file            |
| `FILENAME` | the file being read                                  |
| `FS`       | input field separator; default: runs of blanks       |
| `OFS`      | output field separator; default: one space           |
| `RS`       | input record separator; `""` reads paragraphs        |
| `ORS`      | output record separator; default: newline            |
| `SUBSEP`   | joins the parts of an `a[i, j]` key                  |
| `RSTART` `RLENGTH` | where `match` found it, and how long          |
| `ARGC` `ARGV` | the operands, `ARGV[0]` being `awk`               |
| `OFMT` `CONVFMT` | number to text, in `print` and elsewhere: `%.6g` |

### Fields

```input
alice 30 nyc
bob 25 sf
carol 35 nyc
```

```awk
NR == 1 { print $1, $NF, NF }             # -> alice nyc 3
NR == 2 { $2 = $2 + 1; print }            # -> bob 26 sf
NR == 3 { OFS = "-"; $1 = $1; print }     # -> carol-35-nyc
```

## Strings

| Function                | Answers                                        |
|-------------------------|------------------------------------------------|
| `length(s)`             | characters in s; `length(a)`: elements in a    |
| `substr(s, i, n)`       | n characters of s from position i; first is 1  |
| `index(s, t)`           | where t starts in s, or 0                      |
| `split(s, a, sep)`      | how many pieces; they are `a[1]`, `a[2]` ...   |
| `sub(re, new, target)`  | replaces the first match; `&` in new is the match |
| `gsub(re, new, target)` | replaces every match; answers how many         |
| `match(s, re)`          | where it matches, or 0; sets `RSTART` `RLENGTH` |
| `toupper(s)` `tolower(s)` | s in the other case                          |
| `sprintf(fmt, ...)`     | what `printf` would print                      |
| `s t`                   | s followed by t: joining has no operator       |

```awk
BEGIN {
    s = "hello world"
    print length(s), substr(s, 7, 5), index(s, "o")     # -> 11 world 5
    n = split("a,b,c", part, ",")
    print n, part[3]                                    # -> 3 c
    gsub(/o/, "0", s); print s                          # -> hell0 w0rld
    sub(/w.*/, "[&]", s); print s                       # -> hell0 [w0rld]
    if (match("x=42", /[0-9]+/)) print RSTART, RLENGTH  # -> 3 2
    print toupper("ab") tolower("CD")                   # -> ABcd
}
```

## Numbers

| Spelling                     | Meaning                                   |
|------------------------------|-------------------------------------------|
| `+ - * / % ^`                | arithmetic; `^` is power                  |
| `++ -- += -= *= /= %= ^=`    | change a variable in place                |
| `< <= == != >= >`            | compare; as numbers when both look numeric |
| `c ? a : b`                  | a when c is true, else b                  |
| `int(x)`                     | x without its fraction                    |
| `sqrt exp log sin cos atan2` | the usual functions                       |
| `rand()` `srand(n)`          | a number in [0, 1); set the seed          |

```awk
BEGIN {
    print 7 / 2, int(7 / 2), 7 % 2, 2 ^ 10      # -> 3.5 3 1 1024
    print 1 / 3                                 # -> 0.333333
    print "3x" + 4, "a" < "b", 10 < 9           # -> 7 1 0
}
```

## Arrays

```awk
BEGIN {
    seen["nyc"]++; seen["nyc"]++; seen["sf"]++  # keys are strings
    print seen["nyc"], length(seen)             # -> 2 2
    print ("sf" in seen), ("la" in seen)        # -> 1 0
    delete seen["sf"]
    for (city in seen) print city, seen[city]   # -> nyc 2
    grid[1, 2] = "x"                            # the key is 1 SUBSEP 2
    print ((1, 2) in grid)                      # -> 1
}
# for (k in a) visits the keys in no promised order.
# Naming a[k] creates it; (k in a) asks without creating.
```

## Control flow

```awk
function max(a, b) { return a > b ? a : b }

BEGIN {
    for (i = 1; i <= 3; i++) total += i
    print total                                 # -> 6
    while (total > 1) total = int(total / 2)
    do { total++ } while (total < 5)
    if (total == 5) print "five"; else print "other"    # -> five
    print max(3, 7)                             # -> 7
}
```

| Statement          | Does                                           |
|--------------------|------------------------------------------------|
| `next`             | stop this record, start the rules on the next  |
| `exit N`           | stop reading; `END` runs; N is the exit status |
| `break` `continue` | leave the loop; start its next turn            |
| `return V`         | answer V from a function                       |

## Printing

| In a format | Prints                                              |
|-------------|-----------------------------------------------------|
| `%d` `%i`   | an integer                                          |
| `%s`        | a string                                            |
| `%f` `%e` `%g` | a number: fixed, exponent, the shorter of the two |
| `%x` `%o` `%c` | hexadecimal, octal, the character with that code |
| `%%`        | a percent sign                                      |
| `%-8s`      | at least 8 wide, on the left; without `-`, on the right |
| `%08.3f`    | zero-filled to 8 wide, 3 places after the point     |

```awk
BEGIN {
    printf "%-6s|%4d|%6.2f|\n", "bob", 25, 3.14159  # -> bob   |  25|  3.14|
    printf "%05d %x %c %d%%\n", 42, 255, 65, 9      # -> 00042 ff A 9%
    print "a", "b"                                  # -> a b
    print "a" "b"                                   # -> ab
    OFS = "-"; print "a", "b"                       # -> a-b
}
```

## Input and output

| Spelling                  | Does                                        |
|---------------------------|---------------------------------------------|
| `print > "file"`          | write to file, emptied at its first use     |
| `print >> "file"`         | add to the end of file                      |
| `print \| "cmd"`          | send to the command's standard input        |
| `"cmd" \| getline line`   | read the command's next line into line      |
| `getline line < "file"`   | read file's next line into line             |
| `getline`                 | read the next record into `$0`              |
| `close("file or cmd")`    | finish with it; a later use starts again    |
| `system("cmd")`           | run it; answers its exit status             |

```awk
BEGIN {
    "echo hi" | getline word; print word        # -> hi
    print "b\na" | "sort"; close("sort")        # -> a
                                                # -> b
    print system("exit 2")                      # -> 2
}
```

## Recipes

```input
alice 30 nyc
bob 25 sf
carol 35 nyc
```

### Sum and average the rows that match

```awk
$3 == "nyc" { n++; sum += $2 }
END         { print n, sum, sum / n }           # -> 2 65 32.5
```

### Count by a column

```awk
    { count[$3]++ }
END { print count["nyc"], count["sf"] }         # -> 2 1
```

### The row with the largest value

```awk
$2 > max { max = $2; who = $1 }
END      { print who, max }                     # -> carol 35
```

### Reorder and align columns

```awk
{ printf "%-4s %-6s %3d\n", $3, $1, $2 }
# -> nyc  alice   30
# -> sf   bob     25
# -> nyc  carol   35
```

### The file, last line first

```awk
    { line[NR] = $0 }
END { for (i = NR; i > 0; i--) print line[i] }
# -> carol 35 nyc
# -> bob 25 sf
# -> alice 30 nyc
```

## Differs

| Here                                     | In the awk on most systems     |
|------------------------------------------|--------------------------------|
| numbers are exact fractions              | binary floating point          |
| `/a\|ab/` on `ab` matches `a`: the first alternative | `ab`: the longest  |
| `exit` inside a function is an error     | it exits                       |
| POSIX awk only                           | gawk adds `switch`, `asort`, more |

```awk
BEGIN { print (0.1 + 0.2 == 0.3) }              # -> 1
# Other awks print 0: there 0.1 + 0.2 is 0.30000000000000004.
```

## More

| Where                                | What                               |
|--------------------------------------|------------------------------------|
| `README.md`                          | what is built, and each difference |
| `tests/specs/04-divergences.spec.md` | one case a difference              |
| `make card`                          | runs every program on this page    |

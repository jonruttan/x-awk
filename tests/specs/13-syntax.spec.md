# @weight 1

## awk/syntax -- the awk highlighting grammar

The bundle's lang.xon declares a grammar, `awk`, that x/tool/syntax colours
awk programs with. Its module, `awk/syntax`, imports x-lang libraries and
awk/words only, and registers the grammar as it loads.

The cases share one process, and a registered grammar stays registered, so
the catalogue's case comes first: it finds the grammar through lang.xon,
before anything has imported the module.

### the catalogue finds awk by suffix, by #! and by modeline

```awk
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
    (def root (Str8 replace "/awk/syntax.x" "" (%module-resolve-file "awk/syntax.x")))
    (def tmp (File temp "/tmp/x-awk-spec-langs-"))
    (File close (first tmp))
    (def d (rest tmp))
    (File unlink d)
    (File mkdir d)
    (File symlink root (Str8 append d "/awk"))
    (def was (Sys getenv "X_LANG_DIR"))
    (Sys setenv "X_LANG_DIR" d)
    (Syntax forget!)
    (def row (List find (fn (_ r) (eq? (first r) (lit awk))) (Syntax catalogue)))
    (def name (fn (_ path . text)
      (let ((g (apply Syntax (pair (lit for-file) (pair path text))))) (if (null? g) () (g name)))))
    (def seen
      (list (List ref 1 row)
            (name "x.awk")
            (name "run" "#!/usr/bin/awk -f\n{ print }\n")
            (name "run" "{ print }\n# vi: set ft=awk:\n")
            (name "x.txt")
            (let ((g (Syntax named (lit awk)))) (list (g files) (g interpreters)))))
    (File unlink (Str8 append d "/awk"))
    (File rmdir d)
    (Sys setenv "X_LANG_DIR" (if (null? was) "" was))
    (Syntax forget!)
    (write seen))
```
---
    (awk/syntax awk awk awk () ((".awk") ("awk" "nawk" "gawk" "mawk")))

### a program's spans: comments, strings, regular expressions, names

A keyword is a keyword, a builtin a name, a variable awk sets a constant,
any other name plain.  A / after an operand divides; anywhere else it opens
a regular expression, coloured as a string.

```awk
(do (import x/tool/syntax) (import awk/syntax)
    (write ((Syntax named (lit awk)) spans
      "# c\nBEGIN { FS = \",\" }\n$1 ~ /a\\/b/ { n++; s = s / 2 }\nEND { print length(x) }\n")))
```
---
    ((0 3 comment) (4 5 keyword) (10 1 punct) (12 2 constant) (15 1 operator) (17 3 string) (21 1 punct) (23 1 operator) (24 1 number) (26 1 operator) (28 6 string) (35 1 punct) (38 2 operator) (40 1 punct) (44 1 operator) (48 1 operator) (50 1 number) (52 1 punct) (54 3 keyword) (58 1 punct) (60 5 keyword) (66 6 name) (72 1 punct) (74 1 punct) (76 1 punct))

### a / after a ] or a ) divides, and a bracket expression holds a /

```awk
(do (import x/tool/syntax) (import awk/syntax)
    (write ((Syntax named (lit awk)) spans "a[i]/2 + f(x) / NR; /[/]x/")))
```
---
    ((1 1 punct) (3 1 punct) (4 1 operator) (5 1 number) (7 1 operator) (10 1 punct) (12 1 punct) (14 1 operator) (16 2 constant) (18 1 punct) (20 6 string))

### an unclosed regular expression is an operator, an unclosed string runs to the end

```awk
(do (import x/tool/syntax) (import awk/syntax)
    (write (List map (fn (_ s) ((Syntax named (lit awk)) spans s))
      (list "x ~ /ab" "print \"open"))))
```
---
    (((2 1 operator) (4 1 operator)) ((0 5 keyword) (6 5 string)))

### the grammar's keywords are the ones the interpreter reads

```awk
(do (import awk/words awk-keywords)
    (write (List filter (fn (_ w) (not (eq? (first (first (awk-tokenize w))) (lit kw)))) awk-keywords)))
```
---
    ()

# @weight 2

The lexer: program text to tokens.  Tokens are the lexer's public record --
`(num N)` carries the parsed NUMBER (exact: `1.5` is `3/2`), `(str "s")`
carries the text with escapes already processed, `(ere "pat")` carries the
pattern text for the parser to compile.

## numbers

### an integer

```awk
(write (awk-tokenize "x = 1"))
```
---
    ((name "x") (op "=") (num 1))

### a decimal is exact

```awk
(write (awk-tokenize "1.5"))
```
---
    ((num 3/2))

### a leading-dot decimal

```awk
(write (awk-tokenize ".5"))
```
---
    ((num 1/2))

### an exponent scales exactly

```awk
(write (awk-tokenize "25e-2"))
```
---
    ((num 1/4))

### an e with no digits is not an exponent

```awk
(write (awk-tokenize "1e"))
```
---
    ((num 1) (name "e"))

## strings

### a plain string

```awk
(write (awk-tokenize "\"hi\""))
```
---
    ((str "hi"))

### a backslash-t escape becomes one tab character

```awk
(display (string-length (first (rest (first (awk-tokenize "\"a\\tb\""))))))
```
---
    3

## names and keywords

### BEGIN and print are keywords, braces are ops

```awk
(write (awk-tokenize "BEGIN{print}"))
```
---
    ((kw BEGIN) (op "{") (kw print) (op "}"))

### a name that merely starts with a keyword is a name

```awk
(write (awk-tokenize "printer"))
```
---
    ((name "printer"))

## operators

### two-char operators fold

```awk
(write (awk-tokenize "a==b&&c"))
```
---
    ((name "a") (op "==") (name "b") (op "&&") (name "c"))

### compound assignment

```awk
(write (awk-tokenize "x+=2"))
```
---
    ((name "x") (op "+=") (num 2))

### postfix increment

```awk
(write (awk-tokenize "i++"))
```
---
    ((name "i") (op "++"))

### the field operator

```awk
(write (awk-tokenize "$1"))
```
---
    ((op "$") (num 1))

## slash: division or ERE, by context

### after a name it divides

```awk
(write (awk-tokenize "a/b"))
```
---
    ((name "a") (op "/") (name "b"))

### at expression position it is an ERE

```awk
(write (awk-tokenize "/ab/"))
```
---
    ((ere "ab"))

### after a match operator it is an ERE

```awk
(write (awk-tokenize "x ~ /a+/"))
```
---
    ((name "x") (op "~") (ere "a+"))

### an escaped slash stays inside the pattern

```awk
(write (awk-tokenize "/a\\/b/"))
```
---
    ((ere "a/b"))

## layout

### a comment runs to end of line

```awk
(write (awk-tokenize "a #c\nb"))
```
---
    ((name "a") (nl) (name "b"))

### newline runs collapse to one terminator

```awk
(write (awk-tokenize "a\n\n\nb"))
```
---
    ((name "a") (nl) (name "b"))

### backslash-newline continues the line

```awk
(write (awk-tokenize "a\\\nb"))
```
---
    ((name "a") (name "b"))

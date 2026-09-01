# @weight 2

The parser: tokens to a program.  Items are `(begin STMTS)`, `(end STMTS)`
and `(rule PATTERN ACTION)` -- a nil pattern fires on every record, a nil
action means `print $0`.  EREs arrive compiled: the AST carries the regex
value, not its text.

## items

### a bare action is a rule with no pattern

```awk
(write (awk-parse "{print}"))
```
---
    ((rule () ((print))))

### a bare pattern is a rule with no action

```awk
(write (awk-parse "NR"))
```
---
    ((rule (var "NR") ()))

### BEGIN and END

```awk
(write (awk-parse "BEGIN{x=1}"))
```
---
    ((begin ((expr (assign (var "x") (num 1))))))

### an ERE pattern is compiled at parse time

```awk
(write (awk-parse "/ab/{print}"))
```
---
    ((rule (ere #/ab/) ((print))))

## expressions

### fields and the print list

```awk
(write (awk-parse "{print $1, $2}"))
```
---
    ((rule () ((print (field (num 1)) (field (num 2))))))

### multiplication binds tighter than addition

```awk
(write (awk-parse "BEGIN{x=1+2*3}"))
```
---
    ((begin ((expr (assign (var "x") (bin "+" (num 1) (bin "*" (num 2) (num 3))))))))

### concatenation is juxtaposition

```awk
(write (awk-parse "{print \"a\" \"b\"}"))
```
---
    ((rule () ((print (concat (str "a") (str "b"))))))

### comparison in a pattern

```awk
(write (awk-parse "a==1{print}"))
```
---
    ((rule (cmp "==" (var "a") (num 1)) ((print))))

### a match against a field

```awk
(write (awk-parse "$1~/x/{print}"))
```
---
    ((rule (match (field (num 1)) (ere #/x/)) ((print))))

### compound assignment desugars

```awk
(write (awk-parse "{x+=2}"))
```
---
    ((rule () ((expr (assign (var "x") (bin "+" (var "x") (num 2)))))))

### power is right-associative

```awk
(write (awk-parse "BEGIN{x=2^3^2}"))
```
---
    ((begin ((expr (assign (var "x") (pow (num 2) (pow (num 3) (num 2))))))))

### a builtin call

```awk
(write (awk-parse "{print substr($1,2,3)}"))
```
---
    ((rule () ((print (call "substr" ((field (num 1)) (num 2) (num 3)))))))

## statements

### if with else

```awk
(write (awk-parse "{if(x)print 1;else print 2}"))
```
---
    ((rule () ((if (var "x") (print (num 1)) (print (num 2))))))

### while

```awk
(write (awk-parse "{while(i<3)i++}"))
```
---
    ((rule () ((while (cmp "<" (var "i") (num 3)) (expr (postinc (var "i")))))))

### for

```awk
(write (awk-parse "{for(i=0;i<3;i++)print i}"))
```
---
    ((rule () ((for (assign (var "i") (num 0)) (cmp "<" (var "i") (num 3)) (postinc (var "i")) (print (var "i"))))))

### statements split across lines

```awk
(write (awk-parse "{x=1\ny=2}"))
```
---
    ((rule () ((expr (assign (var "x") (num 1))) (expr (assign (var "y") (num 2))))))

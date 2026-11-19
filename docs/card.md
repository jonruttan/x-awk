# x-awk card

## Run

```sh
echo 'a b' | x -l awk '{print $2}' -> b
echo 'a:b' | x -l awk -- -F: '{print $2}' -> b       # --: awk's options follow
x -l awk -- -v n=3 'BEGIN{print n*2}' -> 6
echo 'a b' | x -l awk '{print n, $1}' n=5 - -> 5 a   # var=value, then stdin
x -l awk 'BEGIN{exit 3}'; echo $? -> 3
x -l awk -- -f PROG FILE...                          # the program from a file
x -l awk                                             # a session, awk loaded
```

## Records

```sh
printf 'a b\nc d\n' | x -l awk 'END{print NR, NF}' -> 2 2
printf 'a b\nc d\n' | x -l awk 'NR==2{print $1}' -> c
printf 'a b\nc d\n' | x -l awk '/c/' -> c d
echo 'a b c' | x -l awk '{print $NF}' -> c
echo 'a b c' | x -l awk '{$2="X"; print}' -> a X c
echo 'a b c' | x -l awk -- -v OFS=- '{$1=$1; print}' -> a-b-c
printf 'a\nb\n\nc\n' | x -l awk -- -v RS= 'END{print NR}' -> 2   # paragraphs
```

## Strings

```sh
x -l awk 'BEGIN{print length("abc"), substr("abcde",2,3)}' -> 3 bcd
x -l awk 'BEGIN{print index("abc","c"), toupper("ab") tolower("CD")}' -> 3 ABcd
x -l awk 'BEGIN{n=split("a,b,c",p,","); print n, p[3]}' -> 3 c
x -l awk 'BEGIN{s="aaa"; sub(/a/,"b",s); print s}' -> baa
x -l awk 'BEGIN{s="aaa"; gsub(/a/,"<&>",s); print s}' -> <a><a><a>
x -l awk 'BEGIN{print match("xxabc",/abc/), RSTART, RLENGTH}' -> 3 3 3
x -l awk 'BEGIN{printf "%.2f|%-4s|%03d\n", 3.14159, "ab", 7}' -> 3.14|ab  |007
```

## Arrays

```sh
x -l awk 'BEGIN{a["k"]=1; print ("k" in a), ("z" in a)}' -> 1 0
x -l awk 'BEGIN{a[1]; a[2]; delete a[1]; print length(a)}' -> 1
x -l awk 'BEGIN{a[1,2]; for(k in a){split(k,p,SUBSEP); print p[2]}}' -> 2
printf 'a\nb\na\n' | x -l awk '{c[$1]++} END{print c["a"]}' -> 2
```

## Input and output

```sh
echo hi | x -l awk '{print | "tr a-z A-Z"}' -> HI
x -l awk 'BEGIN{"echo hi" | getline s; print s}' -> hi
x -l awk 'BEGIN{print system("exit 2")}' -> 2
x -l awk 'BEGIN{while ((getline l < "FILE") > 0) n++; print n}'
x -l awk 'BEGIN{print "x" > "FILE"; close("FILE")}'
```

## Differs

```sh
x -l awk 'BEGIN{print (0.1+0.2==0.3)}' -> 1          # exact; a C awk: 0
x -l awk 'BEGIN{printf "%.0f\n", 2.5}' -> 3          # half up; C doubles: 2
x -l awk 'BEGIN{printf "%x\n", -1}' -> -1            # a C awk wraps it unsigned
x -l awk 'BEGIN{printf "%.12f\n", sqrt(2)}' -> 1.414213562000   # ten digits
x -l awk 'BEGIN{match("ab",/a|ab/); print RLENGTH}' -> 1   # leftmost first
x -l awk 'function f(){exit 3} BEGIN{f()}'           # raises: not built
```

## More

```sh
make test                                 # the suite
make card                                 # this page's rows
less README.md                            # what it does, and each difference
less tests/specs/04-divergences.spec.md   # one case a difference
```

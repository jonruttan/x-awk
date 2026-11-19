#!/bin/sh
# tests/card-run.sh FILE -- run one program of docs/card.md, for the lang
# kit's card check.  X is the x under test; the input is on standard input.
exec "${X:-x}" -l awk -- -f "$1"

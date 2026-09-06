#!/bin/sh
# # x-awk -- POSIX awk on x-lang
#
# ## tests/spec-runner.sh -- the bundle's runner
#
# @description Sources the PLATFORM's spec runner; vendors nothing.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# NOT ONE PATH INTO THE X-LANG SOURCE TREE.  Everything here comes from x
# itself: --share-dir says which tree x reads from (repo root in a checkout,
# share/x installed) and --engine-path says where the engine is.
#
# Set X to point at a particular x; otherwise the one on PATH is used.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X="${X:-x}"

command -v "$X" >/dev/null 2>&1 || {
	echo "x-awk: no x on PATH.  Set X=/path/to/x.sh and retry." >&2
	exit 1
}

X_ROOT="$("$X" --share-dir)"
X_BIN="${X_BIN:-$("$X" --engine-path)}"

# REQUIRED FROM AN INSTALLED TREE: the runner finds its harness from the
# directory holding the ENGINE, which is only true in a checkout.
SPEC_RUNNER_DIR="$X_ROOT/tests"
export SPEC_RUNNER_DIR

# The harness is GENERATED, never committed: it embeds two absolute paths
# that are facts of this machine, not of the bundle.
sh "$BUNDLE/tests/gen-harness.sh" "$X_ROOT" "$BUNDLE"

LANG_LIB="$BUNDLE/tests/lib/harness.gen.x"
# SPEC_PATH is env-overridable so a single spec file can be run in isolation.
SPEC_PATH="${SPEC_PATH:-$BUNDLE/tests/specs}"

# THE SUITE BOOTS FROM A STATE IMAGE OF THE HARNESS, when the platform can
# write one.  tools/dev/image-build.sh images a child that loaded the
# harness and keys the image on everything it depends on -- the harness,
# the platform's lib/, its engine, and awk/ (the KEY-PATH) -- so an edit
# to any of them rewrites it (a few seconds) and a current one is skipped.
# Each spec file then loads in a third of a second instead of booting the
# core and the tower from source.  The writer lives in a CHECKOUT only; an
# installed tree boots from source and says so.  IMG=0 is the control: the
# suite from source, for when the image is the suspect -- one file per
# process there too (SPEC_BATCH=1, the shape the image run has), so the boot
# is the only difference: eight awk files on the interpreted tower overrun
# the runner's allocation ceiling in one process, where the compiled tower
# of the old x-base.x harness did not.
if [ "${IMG:-1}" = 0 ]; then
	SPEC_BATCH="${SPEC_BATCH:-1}"; export SPEC_BATCH
else
	_builder="$X_ROOT/tools/dev/image-build.sh"
	if [ -f "$_builder" ]; then
		if X_BIN="$X_BIN" sh "$_builder" "$LANG_LIB" "$BUNDLE/tests/lib/.images" "$BUNDLE/awk"; then
			X_IMG_DIR="$BUNDLE/tests/lib/.images"; export X_IMG_DIR
		else
			echo "x-awk: no state image (image-build exit $?) -- the suite boots from source" >&2
		fi
	else
		echo "x-awk: no image writer at $_builder (not a checkout) -- the suite boots from source" >&2
	fi
fi

# NO COLLECT AT THE SNIPPET SEAM (x-lang#568/#572): the per-seam heap collect
# killed x-ash's and x-python's suites; x-awk sets the same knob for the same
# reason rather than rediscovering it.
export SPEC_SEAM_COLLECT=0

. "$X_ROOT/tests/spec-runner.sh"

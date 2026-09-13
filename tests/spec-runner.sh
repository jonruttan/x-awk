#!/bin/sh
# # x-awk -- POSIX awk on x-lang
#
# ## tests/spec-runner.sh -- the bundle's runner
#
# @description Sources the platform's spec runner; vendors nothing.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# No path reaches into an x-lang source tree; everything comes from x itself:
# --share-dir says which tree x reads from (repo root in a checkout, share/x
# when installed) and --engine-path says where the engine is.
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

# The platform runner locates its harness relative to the engine binary, which
# sits beside tests/ only in a checkout; a sourced script cannot portably find
# its own path, so the caller sets this.
SPEC_RUNNER_DIR="$X_ROOT/tests"
export SPEC_RUNNER_DIR

# The harness is GENERATED, never committed: it embeds two absolute paths
# that are facts of this machine, not of the bundle.
sh "$BUNDLE/tests/gen-harness.sh" "$X_ROOT" "$BUNDLE"

LANG_LIB="$BUNDLE/tests/lib/harness.gen.x"
# SPEC_PATH is env-overridable so a single spec file can be run in isolation.
SPEC_PATH="${SPEC_PATH:-$BUNDLE/tests/specs}"

# The suite boots from a state image of the harness when the platform can write
# one. tools/dev/image-build.sh images a child that loaded the harness, keyed on
# what it depends on (the harness, the platform's lib/, its engine, and awk/),
# so an edit to any of them rewrites the image and a current one is reused. Each
# spec file then loads in about a second instead of booting x-base.x from
# source.
#
# The writer lives in a checkout only; an installed tree boots from source and
# says so, as does a checkout whose engine predates x-engine-c v0.2.8 (the
# writer refuses x-base.x's compiled tower there; tests/gen-harness.sh has the
# story). IMG=0 is the control: the suite from source, one file per process, so
# the boot is the only difference -- which makes it slow, the price of a control
# that differs in exactly one thing.
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

# No collect at the snippet seam (x-lang#568/#572): the per-seam heap collect
# kills the suites of bundles whose reader holds C-side state, so this sets the
# same knob x-ash and x-python do.
export SPEC_SEAM_COLLECT=0

. "$X_ROOT/tests/spec-runner.sh"

#!/bin/sh
# The gate lives in the lang kit, not here: it is identical in every bundle, so
# one shared copy (tools/lang-kit/) saves an N-repo re-vendor for every fix.
# This file only says where the bundle is and which x to ask for the kit.
#
# Set X to point at a particular x; X_LANG_KIT overrides the kit location.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X="${X:-x}"

KIT="${X_LANG_KIT:-$("$X" --share-dir)/tools/lang-kit}"
[ -f "$KIT/spec-gate.sh" ] || {
	echo "x-awk: no lang kit at $KIT -- set X_LANG_KIT or upgrade x" >&2
	exit 2
}

BUNDLE="$BUNDLE" X="$X" . "$KIT/spec-gate.sh"

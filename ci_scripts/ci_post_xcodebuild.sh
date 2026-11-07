#!/bin/bash
# Xcode Cloud runs this after each xcodebuild action. The workflow may point at
# the workspace (this copy) or at HolmdelApp/Holmdel.xcodeproj (the twin beside
# it); both files must stay identical.
#
# An archive built without HolmdelApp/Config/Shipping.xcconfig still works, it
# is just ~0.8 MB bigger on the phone and ~1.2 MB on the watch, so this warns
# rather than failing the upload. See that file and DECISIONS.md (2026-11-07).
set -uo pipefail

[ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] || exit 0

if [ -z "${XCODE_XCCONFIG_FILE:-}" ]; then
  echo "warning: XCODE_XCCONFIG_FILE is not set on this Xcode Cloud workflow, so packages such as GRDB were built at -O instead of -Osize. Set it to /Volumes/workspace/repository/HolmdelApp/Config/Shipping.xcconfig."
elif [ ! -f "$XCODE_XCCONFIG_FILE" ]; then
  echo "warning: XCODE_XCCONFIG_FILE points at $XCODE_XCCONFIG_FILE, which does not exist in this checkout; the size-optimized package build did not apply."
else
  echo "Size-optimized package build applied from $XCODE_XCCONFIG_FILE."
fi
exit 0

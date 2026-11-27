#!/usr/bin/env bash
# The iCloud container is named in six places: an entitlements file and a
# Swift constant for each of the phone, watch and TV apps. They must agree.
#
# Nothing fails to build when they do not. The app asks CloudKit for a
# container its entitlement does not grant, the open with sync fails, and the
# library quietly opens without it: a device that never syncs, and no error
# anyone sees. See DECISIONS.md (2026-11-22).
#
# python3 rather than PlistBuddy so this runs on a Linux runner too.
set -euo pipefail

declare -a PAIRS=(
  "HolmdelApp/Holmdel/Holmdel.entitlements HolmdelApp/Holmdel/AppDependencies+Factories.swift"
  "HolmdelApp/HolmdelWatchApp/HolmdelWatchApp.entitlements HolmdelApp/HolmdelWatchApp/WatchAppDependencies.swift"
  "HolmdelApp/HolmdelTVApp/HolmdelTVApp.entitlements HolmdelApp/HolmdelTVApp/TVAppDependencies.swift"
)

expected=""
failed=0
for pair in "${PAIRS[@]}"; do
  read -r entitlements source <<<"$pair"

  entitled=$(python3 -c "
import plistlib, sys
with open('$entitlements', 'rb') as handle:
    containers = plistlib.load(handle).get('com.apple.developer.icloud-container-identifiers') or []
if len(containers) != 1:
    sys.exit('expected exactly one iCloud container, found %d' % len(containers))
print(containers[0])
")
  declared=$(sed -n 's/.*cloudKitContainerIdentifier = "\([^"]*\)".*/\1/p' "$source" | head -1)

  if [ -z "$declared" ]; then
    echo "::error::Could not read cloudKitContainerIdentifier from $source." >&2
    failed=1
    continue
  fi
  if [ "$entitled" != "$declared" ]; then
    echo "::error::iCloud container mismatch: $entitlements grants '$entitled' but $source asks for '$declared'. That app will not sync." >&2
    failed=1
  fi
  expected=${expected:-$entitled}
  if [ "$entitled" != "$expected" ]; then
    echo "::error::iCloud container mismatch: $entitlements grants '$entitled' but the phone app uses '$expected'. Those devices will not share a library." >&2
    failed=1
  fi
done

[ "$failed" = 0 ] && echo "iCloud container matches everywhere: $expected"
exit "$failed"

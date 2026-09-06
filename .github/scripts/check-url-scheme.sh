#!/usr/bin/env bash
# The app's registered URL scheme and StationLink's parser must agree.
#
# They silently disagreed once: the Holmdel rename updated Info.plist and
# `handoffActivityType`, but missed `appScheme` on the adjacent line. Nothing
# failed to build. The quick-play widget went on emitting links under the old
# scheme, which the app no longer registered, so tapping a station in the widget
# opened nothing — the kind of break that only shows up on a device, by hand.
#
# python3 rather than PlistBuddy so this runs on a Linux runner too.
set -euo pipefail

PLIST="HolmdelApp/Holmdel/Info.plist"
SOURCE="Packages/RadioDirectory/Sources/RadioDirectory/StationLink.swift"

registered=$(python3 -c "
import plistlib, sys
with open('$PLIST', 'rb') as handle:
    types = plistlib.load(handle).get('CFBundleURLTypes') or []
schemes = [s for entry in types for s in (entry.get('CFBundleURLSchemes') or [])]
if not schemes:
    sys.exit('no CFBundleURLSchemes')
print(schemes[0])
")

declared=$(sed -n 's/.*appScheme = \"\([^\"]*\)\".*/\1/p' "$SOURCE" | head -1)

if [ -z "$declared" ]; then
  echo "::error::Could not read StationLink.appScheme from $SOURCE." >&2
  exit 1
fi

if [ "$registered" != "$declared" ]; then
  echo "::error::URL scheme mismatch — $PLIST registers '$registered' but StationLink.appScheme is '$declared'. Deep links and the quick-play widget will not open the app." >&2
  exit 1
fi

echo "URL scheme matches: $registered"

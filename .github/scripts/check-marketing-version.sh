#!/usr/bin/env bash
# Compare a release tag's version with MARKETING_VERSION in the Xcode project.
#
#   check-marketing-version.sh 0.4.0
#
# Fails (exit 1) when the project disagrees with itself: MARKETING_VERSION must
# appear exactly 12 times and carry one value, or the embedded watch app fails
# App Store validation (docs/RELEASING.md, step 2).
#
# Only warns when that value differs from the tag. v0.4.0 is tagged against a
# tree that reads 0.5.1 on purpose (DECISIONS.md, 2026-11-01), so a hard
# failure here would block the release this check was written after.
set -euo pipefail

tag_version="${1:?usage: $0 <version without leading v>}"
tag_version="${tag_version#v}"
pbxproj="${PBXPROJ:-HolmdelApp/Holmdel.xcodeproj/project.pbxproj}"
expected_count=12

values="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);$/\1/p' "$pbxproj")"
count="$(printf '%s\n' "$values" | grep -c . || true)"
distinct="$(printf '%s\n' "$values" | sort -u | grep . || true)"

if [ "$count" -ne "$expected_count" ]; then
  echo "::error::MARKETING_VERSION appears $count times in $pbxproj; expected $expected_count." >&2
  exit 1
fi

if [ "$(printf '%s\n' "$distinct" | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "::error::MARKETING_VERSION differs between targets: $(printf '%s' "$distinct" | tr '\n' ' ')" >&2
  exit 1
fi

if [ "$distinct" != "$tag_version" ]; then
  echo "::warning::Tag version $tag_version differs from MARKETING_VERSION $distinct. Expected only when it is deliberate (see DECISIONS.md, 2026-11-01)."
else
  echo "MARKETING_VERSION $distinct matches tag on all $expected_count configurations."
fi

#!/usr/bin/env bash
#
# Fails if an MIT-licensed package depends on a GPL-3.0 one.
#
# The convention this enforces is stated in README.md's Licensing section: a
# per-package `LICENSE` file makes that package MIT; everything else inherits
# GPL-3.0 from the root `LICENSE`. Linking a GPL-3.0 package from an MIT one
# makes the MIT label undistributable, and the root `LICENSE` carries no linking
# exception.
#
# This existed because the boundary was documented and then quietly broken:
# `Playback` and `DesignSystem` both linked `Packages/ImageIODownsample` while
# it was GPL-3.0, and the API docs site listed it as excluded-because-GPL at the
# same time. Prefer a check that can fail over a claim in a comment.
#
# Only local path dependencies are checked. Remote packages are covered by
# THIRD_PARTY_LICENSES.md.
#
# Usage: .github/scripts/check-license-boundary.sh [packages-dir]

set -euo pipefail

packages_dir="${1:-Packages}"

if [ ! -d "$packages_dir" ]; then
    echo "error: no such directory: $packages_dir" >&2
    exit 2
fi

# A package is MIT if and only if it ships its own LICENSE file.
is_mit() {
    [ -f "$1/LICENSE" ]
}

violations=0
checked=0

# Package.swift lives at <pkg>/Package.swift; packages nest one level deep
# (Packages/Foo) or two (Packages/Features/BrowseFeature).
while IFS= read -r manifest; do
    pkg_dir=$(dirname "$manifest")
    pkg_name=$(basename "$pkg_dir")

    is_mit "$pkg_dir" || continue
    checked=$((checked + 1))

    # Extract the relative path from each `.package(path: "../Foo")` entry.
    while IFS= read -r rel_path; do
        [ -n "$rel_path" ] || continue
        dep_dir=$(cd "$pkg_dir" && cd "$(dirname "$rel_path")" 2>/dev/null && pwd)/$(basename "$rel_path")
        dep_name=$(basename "$rel_path")

        if [ ! -d "$dep_dir" ]; then
            echo "error: $pkg_name declares .package(path: \"$rel_path\") but $dep_dir does not exist" >&2
            violations=$((violations + 1))
            continue
        fi

        if ! is_mit "$dep_dir"; then
            echo "error: MIT package '$pkg_name' depends on GPL-3.0 package '$dep_name'" >&2
            echo "       $manifest declares .package(path: \"$rel_path\")" >&2
            echo "       Fix by relicensing '$dep_name' MIT (add $dep_dir/LICENSE)," >&2
            echo "       or by removing the dependency." >&2
            violations=$((violations + 1))
        fi
    done < <(grep -oE '\.package\(path: *"[^"]+"' "$manifest" | grep -oE '"[^"]+"' | tr -d '"')
done < <(find "$packages_dir" -name Package.swift -not -path '*/.build/*')

if [ "$checked" -eq 0 ]; then
    echo "error: found no MIT packages under $packages_dir — is the layout right?" >&2
    exit 2
fi

if [ "$violations" -gt 0 ]; then
    echo "" >&2
    echo "$violations license-boundary violation(s). See the Licensing section of README.md." >&2
    exit 1
fi

echo "License boundary OK: $checked MIT package(s), no GPL-3.0 dependencies."

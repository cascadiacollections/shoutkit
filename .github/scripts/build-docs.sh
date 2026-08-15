#!/usr/bin/env bash
#
# Builds the DocC reference for the MIT-licensed packages into `site/api/docs`.
#
# Requires a Mac with Xcode (uses `xcodebuild docbuild`), so it does not run on
# the Linux CI jobs. Shared by both pages.yml jobs: the pull_request job runs it
# to prove the docs still build, and the main-branch job runs it and then
# deploys the result.
#
# Output layout, and why it is a subdirectory:
#
#   site/api/index.html      hand-authored landing page, tracked in git
#   site/api/docs/           merged DocC archive, generated, gitignored
#
# `transform-for-static-hosting` writes its own `index.html` at the output root,
# so pointing it at `site/api` directly would clobber the hand-authored page.
#
# Usage: .github/scripts/build-docs.sh

set -euo pipefail

# The MIT-licensed, reusable packages only — see the Licensing table in
# README.md. GPL packages (feature code, LiveActivity, the app itself) aren't
# part of the SDK surface this site documents.
packages=(
    DesignSystem
    FeatureFlags
    ImageIODownsample
    Persistence
    Playback
    PlaybackEngineAudioStreaming
    RadioDirectory
)

# site/api/index.html is hand-authored (transform-for-static-hosting can't
# produce the marketing copy), so it drifts silently: add a package here and
# its card is simply missing, with nothing to catch it. Assert the two agree
# before spending twenty minutes of runner time on the build.
index_page="site/api/index.html"
missing_cards=0
for package in "${packages[@]}"; do
    route="docs/documentation/$(echo "${package}" | tr '[:upper:]' '[:lower:]')/"
    if ! grep -qF "\"${route}\"" "${index_page}"; then
        echo "error: ${index_page} has no card linking to ${route} (for ${package})" >&2
        missing_cards=$((missing_cards + 1))
    fi
done
# And the reverse: a card pointing at a package that is no longer built 404s.
while IFS= read -r route; do
    module="${route#docs/documentation/}"
    module="${module%/}"
    found=0
    for package in "${packages[@]}"; do
        [ "$(echo "${package}" | tr '[:upper:]' '[:lower:]')" = "${module}" ] && found=1 && break
    done
    if [ "${found}" -eq 0 ]; then
        echo "error: ${index_page} links to ${route}, which no package in this script builds" >&2
        missing_cards=$((missing_cards + 1))
    fi
done < <(grep -oE 'docs/documentation/[a-z]+/' "${index_page}" | sort -u)

if [ "${missing_cards}" -gt 0 ]; then
    echo "" >&2
    echo "${missing_cards} mismatch(es) between ${index_page} and the package list in $0." >&2
    exit 1
fi

work_dir="${RUNNER_TEMP:-$(mktemp -d)}"
archives_dir="${work_dir}/archives"
rm -rf "${archives_dir}"
mkdir -p "${archives_dir}"

for package in "${packages[@]}"; do
    echo "::group::${package}"
    derived_data="${work_dir}/dd-${package}"

    xcodebuild docbuild \
        -workspace ShoutKit.xcworkspace \
        -scheme "${package}" \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "${derived_data}"

    # docbuild produces a .doccarchive for every documentable target in the
    # scheme's dependency graph, not just ${package} itself — e.g. building
    # DesignSystem's docs also archives RadioDirectory, Playback, and
    # ImageIODownsample along the way. Match by exact name; a wildcard
    # first-match here silently serves a dependency's docs under the wrong
    # package's route.
    archive=$(find "${derived_data}" -name "${package}.doccarchive" -print -quit)
    if [ -z "${archive}" ]; then
        echo "No ${package}.doccarchive produced (found: $(find "${derived_data}" -name '*.doccarchive' -exec basename {} \; | tr '\n' ' '))" >&2
        exit 1
    fi

    cp -R "${archive}" "${archives_dir}/${package}.doccarchive"
    echo "::endgroup::"
done

# Merge into ONE archive rather than transforming each separately. Six
# independent archives means six disconnected search indexes and no
# cross-package link resolution — and this dependency graph is deliberately
# seam-heavy, so that matters: PlaybackEngineAudioStreaming's doc comments
# reference ``RadioPlaybackEngine`` from Playback, DesignSystem's public
# signatures name RadioDirectory's `Station`, and so on. Unmerged, every one of
# those renders as dead text instead of a link.
echo "::group::merge"
merged="${work_dir}/ShoutKit.doccarchive"
rm -rf "${merged}"
# shellcheck disable=SC2046 # intentional word splitting over the archive list
xcrun docc merge $(printf '%s\n' "${archives_dir}"/*.doccarchive) \
    --output-path "${merged}" \
    --synthesized-landing-page-name "ShoutKit"
echo "::endgroup::"

echo "::group::transform-for-static-hosting"
rm -rf site/api/docs
xcrun docc process-archive transform-for-static-hosting "${merged}" \
    --output-path site/api/docs \
    --hosting-base-path "shoutkit/api/docs"
echo "::endgroup::"

echo "Docs built into site/api/docs"

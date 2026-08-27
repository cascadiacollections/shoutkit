# Releasing ShoutKit

How to cut a release, and what a release does and does not currently include.

Written on 2026-08-13, when the repo had **zero git tags** and `release.yml` had never once
run. Treat anything here that hasn't actually been executed as untested — the steps are
derived from reading the workflow, and the first real run is the one that proves them.

## What a release is, today

`release.yml` is triggered by pushing a `v*.*.*` tag. It does exactly one thing: extract the
matching section from `CHANGELOG.md` and open a **draft** GitHub Release with it as the body.

It does **not** sign, archive, upload to TestFlight, or submit to the App Store. Its own
header says so, and the reason is that no Apple signing secrets are configured in this repo.
So "cutting a release" currently means *publishing release notes and a source tag*, not
shipping a binary to anyone. Distribution is still done by hand from Xcode.

That gap is the honest state of things and should be closed deliberately rather than
discovered mid-release. See "What's still missing" below.

## The steps

Everything before the tag happens in a normal PR. **The tag comes last, after that PR is
merged**, because the workflow reads `CHANGELOG.md` at the tagged commit.

1. **Cut the changelog over.** Rename `## [Unreleased]` to `## [X.Y.Z] — YYYY-MM-DD` and add
   a fresh empty `## [Unreleased]` above it. This is the step `release.yml` will fail on if
   skipped, by design:

   ```
   ::error::CHANGELOG.md has no '## [X.Y.Z]' section. Cut the changelog over from
   [Unreleased] before tagging.
   ```

   The extractor matches on the `## [X.Y.Z]` prefix, so trailing text after the version is
   fine (`## [0.4.0] — 2026-08-13` works).

2. **Bump `MARKETING_VERSION`.** It appears **twelve times** in
   `ShoutKitApp/ShoutKitApp.xcodeproj/project.pbxproj` — six configurations across the app,
   widgets, and tests, and six more across the watch app, watch widgets, and tvOS app. It is
   *not* in an xcconfig, so there is no single place to change it.

   **All twelve must match.** On 2026-08-13 they did not: the phone app read `0.2.0` while
   the watch and tvOS targets read `0.3.0`. That is not cosmetic — an embedded watch app
   whose `CFBundleShortVersionString` differs from its host app's fails App Store validation,
   and the watch app only became embedded at all in #166.

   ```sh
   grep -c 'MARKETING_VERSION = X.Y.Z;' ShoutKitApp/ShoutKitApp.xcodeproj/project.pbxproj
   # must print 12
   ```

3. **Land the PR**, with CI green.

4. **Tag the merge commit and push it.**

   ```sh
   git checkout main && git pull --ff-only
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

   Note `release.yml` matches `v*.*.*` — the tag carries the `v`, the CHANGELOG heading does
   not.

5. **Check the workflow ran and review the draft.** It is a *draft*: nothing is public until
   someone publishes it. Read the extracted notes before publishing — the extractor takes
   everything between your heading and the next `## [`, so a malformed heading silently
   changes what ships as the notes.

6. **Publish the release** on GitHub once the notes read correctly.

## Signing off a release

There is no automated verification that the tagged commit is shippable beyond normal CI.
Before tagging, confirm by hand:

- `swiftlint --strict` is clean (CI enforces this).
- The simulator test plan passes (CI enforces this).
- The watch payload is embedded — CI asserts this since #166.
- The app icon is the real one, not the programmatic placeholder. **As of 2026-08-13 it is
  still the placeholder**, which is why no release before that date should be treated as
  publicly listable.

## What's still missing

Tracked here rather than in `docs/ROADMAP.md` because these are release *mechanics*, and the
roadmap has a habit of drifting on things nobody re-checks:

- **No signing secrets, so no automated TestFlight or App Store upload.** Every binary that
  has ever reached a device was built by hand from Xcode.
- **No `CURRENT_PROJECT_VERSION` (build number) automation.** It is `1` everywhere and has
  never been incremented. TestFlight rejects a duplicate build number for the same version,
  so this bites the second time a version is uploaded, not the first.
- **No professional app icon.** Flagged swap-before-public-release since 0.2.0.
- **No verification that the tag matches `MARKETING_VERSION`.** Pushing `v0.5.0` against a
  tree that still reads `0.4.0` produces a release whose notes and binary disagree, and
  nothing currently catches it. A CI check comparing the two would be a cheap fix, and is
  exactly the kind of "assert the thing you believe" check this repo already does for the
  Pulse symbols and the watch payload.

## History note

`0.1.0`, `0.2.0`, and `0.3.0` appear in `CHANGELOG.md` and `docs/releases/` but were never
tagged and never released to anyone — they were internal milestones. `v0.4.0` is the first
real release. See `DECISIONS.md` (2026-08-13) for why the numbering continues from those
milestones rather than restarting or retroactively tagging them.

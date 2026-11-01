# Releasing Holmdel

How to cut a release, and what a release does and does not currently include.

Written on 2026-08-13, when the repo had **zero git tags** and `release.yml` had never once
run. Treat anything here that hasn't actually been executed as untested — the steps are
derived from reading the workflow, and the first real run is the one that proves them.

## What a release is, today

`release.yml` is triggered by pushing a `v*.*.*` tag. It does exactly one thing: extract the
matching section from `CHANGELOG.md` and open a **draft** GitHub Release with it as the body.

It does **not** sign, archive, upload to TestFlight, or submit to the App Store. Its own
header says so, and the reason is that no Apple signing secrets are configured in GitHub
Actions. Cutting the GitHub release publishes notes and a source tag. The binary testers
install is the Xcode Cloud archive described under "TestFlight uploads" below. A one-off
archive from Xcode Organizer still works, and is what `docs/TESTFLIGHT.md` walks through
when a build has to be external-eligible by hand.

App Store submission, build numbers, and the version/tag check are still open. See
"What's still missing" below.

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
   `HolmdelApp/Holmdel.xcodeproj/project.pbxproj` — six configurations across the app,
   widgets, and tests, and six more across the watch app, watch widgets, and tvOS app. It is
   *not* in an xcconfig, so there is no single place to change it.

   **All twelve must match.** On 2026-08-13 they did not: the phone app read `0.2.0` while
   the watch and tvOS targets read `0.3.0`. That is not cosmetic — an embedded watch app
   whose `CFBundleShortVersionString` differs from its host app's fails App Store validation,
   and the watch app only became embedded at all in #166.

   ```sh
   grep -c 'MARKETING_VERSION = X.Y.Z;' HolmdelApp/Holmdel.xcodeproj/project.pbxproj
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

## TestFlight uploads (Xcode Cloud)

Pushes to `main` archive in Xcode Cloud and upload to TestFlight. The workflow
itself — start condition, signing, archive action, TestFlight post-action — is
configured in App Store Connect. This repo only has the product manifest at
`HolmdelApp/Holmdel.xcodeproj/xcshareddata/xcodecloud/manifest.json`.

A push uploads only when it changes something that ships. The check is
`.github/scripts/testflight-changes.sh`, run from `ci_scripts/ci_post_clone.sh`
(and the identical hook next to the xcodeproj). It diffs the commit against its
first parent.

**These paths upload a build.** Anything not listed in the next group does too,
including a path the repo does not have yet.

- `HolmdelApp/**` — app, watch, widget, and tvOS sources, tests, resources,
  `Localizable.xcstrings`, privacy manifests, Info.plists, entitlements,
  xcconfigs, assets, and `project.pbxproj` / schemes / the test plan.
- `Packages/**` — library code, tests, DocC, `Package.swift`, and
  `Package.resolved`. A Dependabot or hand edit of a lockfile changes the
  binary, so it uploads. A CodeQL or Actions bump does not.
- `Holmdel.xcworkspace/**` — the workspace and its SwiftPM lockfile.

**These paths do not upload**, and only when every file in the push is one of
them:

- `.github/**` — Actions workflows, Dependabot, CodeQL, CI scripts.
- `docs/**` — documentation.
- `site/**` — the marketing site.
- `ci_scripts/**` and `HolmdelApp/ci_scripts/**` — the skip hook itself.
- Markdown outside the shipping trees (`README.md`, `CHANGELOG.md`,
  `DECISIONS.md`, and the other root `*.md` files).
- `.editorconfig`, `.gitignore`, `.git-blame-ignore-revs`, `.swiftformat`,
  `.swiftlint.yml`, `LICENSE`.

`HolmdelApp/ci_scripts/` is the one directory inside `HolmdelApp/` that does
not upload. It is the Xcode Cloud hook, not the app.

To force a build anyway:

- **Manual Start or Rebuild** of the Xcode Cloud workflow, in Xcode or App
  Store Connect. Add a Manual Start condition on `main` if the workflow does
  not already have one. This is the force hatch that works even when the file
  rule below would not have started a run.
- A commit message containing `[testflight]` or `[ci build]`. This only changes
  the post-clone script. It cannot start a run the file rule suppressed.

GitHub Actions has no TestFlight workflow to dispatch: Actions has no Apple
signing credentials, and adding a `workflow_dispatch` that cannot upload would
not put a build in front of testers.

### What to set in App Store Connect

On the workflow that archives `main` and posts to TestFlight:

1. Open the **Branch Changes** start condition for `main`.
2. Set **Files and Folders** to **Custom Conditions**.
3. Choose **Don't start a build if all changed files match**
   (`DO_NOT_START_IF_ALL_FILES_MATCH`). A mixed commit (site plus a Swift file)
   still builds. Do not choose **Start a build if any file matches** with these
   folders — that inverts the rule and stops app builds.
4. Add matchers for the directories `.github`, `docs`, `site`, and `ci_scripts`.
   Add filename matchers for the root metadata files if you want those pushes
   to avoid starting a run at all. The post-clone script already stops them if
   a run does start.
5. Confirm the workflow has a **Manual Start** condition for `main`.

The same files rule belongs on the branch condition only. A pull-request start
condition that runs tests should keep building docs-only PRs; the script does
not cancel pull-request, tag, or scheduled runs.

Until step 3 is saved, a non-app push still starts a run. The post-clone script
then exits 1 with a `BUILD SKIPPED` banner before the archive, so testers still
do not get a build. The run is marked failed. That failure is the skip. After
step 3, those pushes do not start a run.

### How to verify

On a machine with the repo:

```sh
.github/scripts/testflight-changes.sh --self-test
git diff --name-only HEAD^ HEAD | .github/scripts/testflight-changes.sh --classify
```

`--classify` prints `build` (exit 0) or `skip` (exit 10). CI runs `--self-test`
as the `TestFlight path rules` job.

After this lands on `main`:

- The merge commit only touches the gate, docs, and CI. Xcode Cloud should not
  upload it. Before the App Store Connect change, the run stops in
  `ci_post_clone` and the log contains `BUILD SKIPPED`. After the change, no
  run starts.
- A later commit that touches `HolmdelApp/` or `Packages/` archives and shows
  up in TestFlight.
- Manual Start on a docs-only tip still archives. The log says
  `TestFlight gate: manual start; building.`

## What's still missing

Tracked here rather than in `docs/ROADMAP.md` because these are release *mechanics*, and the
roadmap has a habit of drifting on things nobody re-checks:

- **No Apple signing secrets in GitHub Actions, so Actions does not upload.** TestFlight
  uploads are the Xcode Cloud workflow above, using Apple-managed signing. App Store
  submission is still a separate step.
- **No `CURRENT_PROJECT_VERSION` (build number) automation.** It is now defined once at the
  project level, but still has to be incremented manually. TestFlight rejects a duplicate
  build number for the same version, so this bites the second time a version is uploaded,
  not the first.
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

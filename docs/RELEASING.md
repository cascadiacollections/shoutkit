# Releasing Holmdel

How to cut a release, and what a release does and does not currently include.

Written on 2026-08-13, when the repo had **zero git tags** and `release.yml` had never once
run. `v0.4.0` was first tagged on 2026-08-30 and drafted on 2026-09-02. On 2026-11-07 the
tag was moved to `9c3363e` and that draft was replaced with a new one, **Holmdel 0.4.0**,
which is still unpublished. The checklist below is the state of that first release as of
2026-11-07. Treat any step that still has not been executed as untested.

## v0.4.0 — what is left for Kevin

The tag question is settled (below). Publishing the draft and anything in App Store
Connect are still yours to do. Nothing in this section was submitted anywhere.

### Version and tag

Checked 2026-11-01. No version numbers were rewritten.

- **`MARKETING_VERSION` is `0.5.1` in all twelve target configurations** in
  `HolmdelApp/Holmdel.xcodeproj/project.pbxproj`. They match each other. Info.plists for the
  iOS app, widgets, watch app, watch widgets, and tvOS app all read
  `CFBundleShortVersionString` = `$(MARKETING_VERSION)` and `CFBundleVersion` =
  `$(CURRENT_PROJECT_VERSION)`. None hardcodes a version.
- **`CURRENT_PROJECT_VERSION` is `2`**, set once on the project-level Debug configuration and
  once on Release. Targets inherit it. There is no per-target override.
- **Package manifests do not carry an app version.** Every `Package.swift` is
  `swift-tools-version: 6.4` (the compiler). The libraries are versioned by the repo tag.
- **Do not set the marketing version back to 0.4.0.** TestFlight already has **0.5.1 (31)**,
  archived from `965dc6d` and uploaded 2026-10-25 (`docs/TESTFLIGHT.md`). The 0.5.0 bump was
  a fresh build-number namespace for that upload, not a changelog cut (`DECISIONS.md`,
  2026-09-06); 0.5.1 followed so every target matched. A store version has to be higher than
  the last approved one, and a new archive at 0.4.0 would disagree with the only build
  testers have. The next archive of 0.5.1 needs a build number **greater than 31**. The
  committed `2` would be rejected as a duplicate or lower build on that train. Bump it in
  the archive you upload; this tree was left at `2` so a guessed `32` does not collide with
  a build already sitting in Organizer.
- **The tag `v0.4.0` points at `9c3363e`** (`ci: harden workflows for OpenSSF Scorecard`,
  2026-11-06), moved there on 2026-11-07 from `32693e35` (2026-08-30). That commit is the
  last one before the 2026-11-07 binary-size work, so the tree matches the `[0.4.0]` section
  of `CHANGELOG.md` exactly; the size work is under `[Unreleased]` and goes in the next
  release. `DECISIONS.md` (2026-11-07) has the reasoning.
- **The draft was created by hand, not by `release.yml`.** `9c3363e`'s message ends in
  `[skip ci]`, and GitHub applies that to tag pushes, so the push did not run the workflow.
  The draft was made with the workflow's own extraction and `gh release create` command, and
  is titled **Holmdel 0.4.0**. `release.yml` now also takes a `workflow_dispatch` tag input
  for exactly this case.

### QA issues

None of these three block the GitHub draft or the source tag. None is a known crash on the
shipping path. They do limit what the App Store listing and the release notes may claim.

| Issue | What it is | Blocks 0.4.0? |
|---|---|---|
| [#147](https://github.com/cascadiacollections/shoutkit/issues/147) | Bluetooth / AVRCP artwork has not been watched on a car. The code change is in the tree; the original Tesla report is unverified. | No for the tag and for TestFlight. Yes for any sentence that says car stereos now show the right cover. The changelog says the image is offered only once it is in hand, and points at this issue. |
| [#148](https://github.com/cascadiacollections/shoutkit/issues/148) | No cold-launch or memory baseline is collected per build. Same shape as coverage: measure later, no threshold yet. | No. |
| [#149](https://github.com/cascadiacollections/shoutkit/issues/149) | Mini-player, tab bar, and Now Playing are unchecked at arbitrary window sizes (iPhone Mirroring, iPhone-on-iPad). Needs a device or a Mac. Related open layout item: #145, `StationCard` width vs Dynamic Type. | No for the tag. Worth a pass before the first App Store submission if you want a layout sign-off. |

[#146](https://github.com/cascadiacollections/shoutkit/issues/146) is still open for the
three flags that were neither promoted nor deleted: `geoStations`, `prewarmStations`,
`liveActivity`. `recommendations` was deleted. `diagnostics` stays internal-only on purpose.
That is not a release blocker as long as the notes keep them under "Not yet enabled", which
they now do.

### App Store and TestFlight metadata

Pushes to `main` that change the app upload to TestFlight from Xcode Cloud. A push that
only touches docs, the site, or GitHub Actions does not; see "TestFlight uploads" below.
Merging this checklist is that kind of push. `release.yml` does not sign or upload, and
there is no fastlane metadata directory. A hand archive is still how a build is made
external-eligible (`docs/TESTFLIGHT.md`).

Already in the tree:

- Bundle id `com.cascadiacollections.holmdel`. App Store Connect record **Squan** (6809239472)
  is the one `docs/TESTFLIGHT.md` points at. The home-screen name is **Holmdel**. Pick one
  public name before the store listing; the GitHub release title should be Holmdel.
- `LSApplicationCategoryType` = `public.app-category.music`.
- `ITSAppUsesNonExemptEncryption` = false on the iOS, watch, widget, watch-widget, and tvOS
  plists.
- Privacy manifests on the iOS app, the watch app, and the tvOS app: no tracking, no collected
  data types, UserDefaults reason `CA92.1`. The widget and watch-widget extensions have no
  `PrivacyInfo.xcprivacy`. Their sources do not call UserDefaults or the file-timestamp APIs;
  confirm the next upload does not warn ITMS-91053.
- iPhone icon is `Squan-AppIcon` (Icon Composer). Watch and tvOS still use their earlier
  `AppIcon` / brand-asset icons. The generated placeholder is no longer what the iPhone
  target compiles.
- Public TestFlight link: https://testflight.apple.com/join/ZBSBTbRU — external group, build
  0.5.1 (31).
- Support destinations in the app are the GitHub repo, issues, and sponsors
  (`ProjectLinks.swift`). There is no separate support email.

Still to do in App Store Connect, by hand:

- **Screenshots.** None are in the repo. The store requires them for the iPhone sizes you
  ship and for iPad. Capture them from a Release build that shows Holmdel, not the old
  ShoutKit name, and not Live Activity or CarPlay.
- **Privacy policy URL.** `site/index.html#privacy` exists. The FAQ answer says network
  traffic is directory queries, streams, and play reports. It does not mention album-art
  lookups, which send artist and title to the iTunes Search API when Settings → Privacy →
  Fetch Album Artwork is on (the default). The nutrition labels should match the manifests
  (no tracking, no collected data types) and the questionnaire should be ready to explain
  those requests. Point the listing at a URL you will keep up.
- **Support URL.** GitHub issues will do. Set it on the version.
- **Age rating, subtitle, description, keywords, and the Mac availability checkbox.** Mac
  Catalyst is a destination of the Holmdel scheme. The site still calls Mac a source
  preview. Decide whether this submission offers the Mac build.
- **tvOS is a separate submission** (`com.cascadiacollections.holmdel.tv`) with its own
  privacy manifest and its own screenshots. It is not part of the iOS archive.
- **Name and claims on the marketing site.** `site/index.html` says CarPlay, Apple Watch,
  and Apple TV are supported, and the structured data repeats CarPlay. CarPlay does not
  launch. The Halloween promo on that page ended 2026-11-01 00:00 Pacific. README's
  capabilities section still describes the Live Activity as part of the shipping app. Fix
  that copy before the listing quotes it. The release notes do not claim those features.
- **Settings copy.** Privacy footnotes mention geo-stations and Share diagnostics. Both
  controls are inert in Release unless an internal flag is forced on. Fine for TestFlight;
  confusing on a first store page if a reviewer opens Settings.
- **Archive with `GIT_COMMIT_SHA` set** to the short commit (`Config/Release.xcconfig`
  defaults it to `local`). Settings → About should show `0.5.1 (N) · <sha>` on the build
  you upload.
- **Export the next binary as 0.5.1 with a new build number**, not as 0.4.0. The GitHub
  release can still be titled 0.4.0; say so in the release body only if you want testers to
  see both numbers. The changelog section itself does not mention 0.5.1.

### Publishing the draft

1. ~~Decide the tag question above.~~ Done 2026-11-07: `v0.4.0` is on `9c3363e`.
2. ~~Put the `[0.4.0]` section of `CHANGELOG.md` in the draft body.~~ Done: the body is that
   section as extracted from the tagged commit, ending with "Not yet enabled".
3. Read the "Not yet enabled" section once more against `FeatureCatalog` before you publish.
4. Publish the GitHub Release yourself. `release.yml` never edits an existing draft and never
   publishes; it creates a new draft only when a tag is pushed or the workflow is run by hand.

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

   As of 2026-11-01 all twelve read `0.5.1`. Leave them there for the `v0.4.0` notes; the
   checklist at the top of this file says why.

3. **Land the PR**, with CI green.

4. **Tag the merge commit and push it.**

   ```sh
   git checkout main && git pull --ff-only
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

   Note `release.yml` matches `v*.*.*` — the tag carries the `v`, the CHANGELOG heading does
   not.

   **A tag on a `[skip ci]` commit does not start the workflow.** GitHub reads the tagged
   commit's message on tag pushes too, and Dependabot and CI-only commits here often carry
   it. Check that a run appeared. If none did, run **Release** by hand from the Actions tab
   (or `gh workflow run release.yml -f tag=vX.Y.Z`); it checks out that tag and does the
   same thing.

5. **Check the workflow ran and review the draft.** The run also compares the tag with
   `MARKETING_VERSION`: it fails if the twelve entries disagree with each other, and warns
   (without failing) if they differ from the tag. It is a *draft*: nothing is public until
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
- The iPhone icon is the Icon Composer beacon (`Squan-AppIcon`), adopted 2026-09-07. Watch
  and tvOS still compile their earlier icon sets. Confirm those are the icons you want on
  each store listing.

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

### Size-optimized package build

Set one environment variable on the TestFlight workflow (**Environment** → **Environment
Variables**):

```
XCODE_XCCONFIG_FILE = /Volumes/workspace/repository/HolmdelApp/Config/Shipping.xcconfig
```

`xcodebuild` applies that file to every target, Swift packages included, so GRDB and the
other remote packages build at `-Osize`. No project or manifest setting can reach them.
It makes the phone binary 0.8 MB smaller and the watch app 1.2 MB smaller
(`DECISIONS.md`, 2026-11-07). Without it the build still succeeds, just larger, and
`ci_scripts/ci_post_xcodebuild.sh` prints a warning in the archive log.

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
  submission is still a separate step. A one-off Organizer archive is still how a build is
  made external-eligible by hand (`docs/TESTFLIGHT.md`).
- **No `CURRENT_PROJECT_VERSION` (build number) automation.** It is defined once at the
  project level (`2` as of 2026-11-01) and still has to be incremented by hand. TestFlight
  already has 0.5.1 (31), so the next upload of that version must be build 32 or higher.
  The committed `2` is behind the upload on purpose; see the checklist above.
- **iPhone icon is in place; watch and tvOS icons were not part of that swap.**
- **The tag-vs-`MARKETING_VERSION` check only warns.** `release.yml` runs
  `.github/scripts/check-marketing-version.sh`, which fails when the twelve entries disagree
  with each other but only warns when they differ from the tag, because `v0.4.0` against
  `0.5.1` is deliberate. Make the mismatch a failure once the tag and marketing version are
  back in step (the first release after 0.5.1).

## History note

`0.1.0`, `0.2.0`, and `0.3.0` appear in `CHANGELOG.md` and `docs/releases/` but were never
tagged and never released to anyone — they were internal milestones. `v0.4.0` is the first
real release: tagged 2026-08-30, drafted 2026-09-02, re-tagged onto `9c3363e` and re-drafted
2026-11-07, unpublished. See `DECISIONS.md`
(2026-08-13 and 2026-11-01) for why the numbering continues from those milestones, and why
the binary's marketing version is 0.5.1 while this release is still called 0.4.0.

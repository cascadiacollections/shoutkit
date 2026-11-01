# Releasing Holmdel

How to cut a release, and what a release does and does not currently include.

Written on 2026-08-13, when the repo had **zero git tags** and `release.yml` had never once
run. `v0.4.0` has since been tagged (2026-08-30) and `release.yml` has drafted a GitHub
Release from it (2026-09-02). That draft is still unpublished. The checklist below is the
state of that first release as of 2026-11-01. Treat any step that still has not been
executed as untested.

## v0.4.0 — what is left for Kevin

Do not publish the draft, move the tag, or upload to App Store Connect until the items
marked as blockers are decided. Nothing in this section was submitted anywhere.

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
- **The tag `v0.4.0` is not current `main`.** It points at `32693e35`
  (`chore(release): cut 0.4.0`, 2026-08-30). The draft release
  ([untagged draft](https://github.com/cascadiacollections/shoutkit/releases/tag/untagged-4d62960440c8df67c7f6),
  title still "ShoutKit 0.4.0") was created from that commit. Pasting new notes into the
  draft does not move the tag. Publishing the draft as it is attached today publishes the
  August 30 tree.
- **To publish notes that describe current `main`, move the tag after this branch is merged,
  then paste the body.** This repo does not do that move. Suggested order, once you want it:
  1. Merge the notes PR.
  2. Delete the draft, or `release.yml`'s `gh release create` will fail because a release
     for `v0.4.0` already exists.
  3. Delete the remote tag and push `v0.4.0` on the merge commit. `release.yml` will open a
     new draft from `CHANGELOG.md`'s `[0.4.0]` section. Read it before publishing.
  4. Retitle the draft to **Holmdel 0.4.0**. The workflow's title template is already
     `Holmdel X.Y.Z`; the existing draft predates the rename.
- **Leaving the tag where it is** is the other honest choice: publish the August 30 notes
  (with the feature-flag corrections from this changelog) and do not describe Mac Catalyst,
  the rename, or the later playback fixes as part of that tag. The `[0.4.0]` section in
  `CHANGELOG.md` is written for the first choice. If you take the second, do not paste it
  onto the August tag.

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

Distribution is still by hand from Xcode. `release.yml` does not sign or upload. There is no
fastlane metadata directory.

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

1. Decide the tag question above.
2. Paste the `[0.4.0]` section of `CHANGELOG.md` (everything after the heading, through
   "Not yet enabled", and not the 0.2.0 milestone) as the draft body. That text is also in
   the pull request that added this checklist.
3. Read the "Not yet enabled" section once more against `FeatureCatalog` before you publish.
4. Publish the GitHub Release yourself. Do not expect `release.yml` to edit the existing
   draft; it only runs when a tag is pushed, and it creates a draft rather than publishing.

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
- The iPhone icon is the Icon Composer beacon (`Squan-AppIcon`), adopted 2026-09-07. Watch
  and tvOS still compile their earlier icon sets. Confirm those are the icons you want on
  each store listing.

## What's still missing

Tracked here rather than in `docs/ROADMAP.md` because these are release *mechanics*, and the
roadmap has a habit of drifting on things nobody re-checks:

- **No signing secrets, so no automated TestFlight or App Store upload.** Every binary that
  has ever reached a device was built by hand from Xcode.
- **No `CURRENT_PROJECT_VERSION` (build number) automation.** It is defined once at the
  project level (`2` as of 2026-11-01) and still has to be incremented by hand. TestFlight
  already has 0.5.1 (31), so the next upload of that version must be build 32 or higher.
  The committed `2` is behind the upload on purpose; see the checklist above.
- **iPhone icon is in place; watch and tvOS icons were not part of that swap.**
- **No verification that the tag matches `MARKETING_VERSION`.** That gap is no longer
  hypothetical: `v0.4.0` is tagged and the tree reads `0.5.1`. Nothing in CI catches it.
  A check comparing the two would be the same kind of assertion this repo already makes for
  the Pulse symbols and the watch payload. Until it exists, the checklist above is the check.

## History note

`0.1.0`, `0.2.0`, and `0.3.0` appear in `CHANGELOG.md` and `docs/releases/` but were never
tagged and never released to anyone — they were internal milestones. `v0.4.0` is the first
real release: tagged 2026-08-30, drafted 2026-09-02, unpublished. See `DECISIONS.md`
(2026-08-13 and 2026-11-01) for why the numbering continues from those milestones, and why
the binary's marketing version is 0.5.1 while this release is still called 0.4.0.

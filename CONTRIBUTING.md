# Contributing to ShoutKit

Thanks for your interest! ShoutKit is a native iOS 27 SwiftUI internet-radio client built in the
open. This document covers everything you need to build, test, and land a change.

## Building

Requirements: Xcode 27 with the iOS 27 SDK (the package manifests are `swift-tools-version: 6.4`
and the deployment floor is iOS 27, so an earlier Xcode can't open or build the project — see
`DECISIONS.md`).

```sh
xcodebuild -workspace ShoutKit.xcworkspace -scheme ShoutKit \
  -destination 'generic/platform=iOS Simulator' build
```

No API key or account is needed — station discovery defaults to the keyless
[Radio-Browser](https://www.radio-browser.info) community directory. (An optional SHOUTcast key
can be supplied via `ShoutKitApp/Config/Secrets.xcconfig`; see the README.)

## Running tests

These package suites run on the mac host — the same set CI's `host-tests` job runs:

```sh
for pkg in RadioDirectory Playback Persistence ImageIODownsample FeatureFlags \
           BrowseFeatureCore SearchFeatureCore; do
  (cd "Packages/$pkg" && swift test --disable-xctest)
done
```

(CI passes `--disable-xctest` to skip the legacy XCTest pass, which segfaults under the current
Xcode 27 beta xctest agent; every suite is Swift Testing, so the real tests run either way — see
the note in `.github/workflows/ci.yml`.)

The iOS-only production types (`AudioStreamingPlaybackEngine`, `NowPlayingCenter`) are gated behind
`#if canImport(UIKit)`, so the Playback controller/state-machine tests execute against fakes on
any platform; the gated types compile as part of the app build.

If `swift test` fails at the `CodeSign` step with "resource fork, Finder information, or similar
detritus not allowed", your build wrote provenance extended attributes onto the test bundle
(seen on some macOS betas). Workaround:

```sh
BUNDLE=.build/out/Products/Debug/<TargetName>Tests.xctest
xattr -cr "$BUNDLE"
codesign --force --sign - --timestamp=none --generate-entitlement-der "$BUNDLE"
swift test --skip-build
```

## Project conventions

- **Swift 6 strict concurrency is non-negotiable** — all packages build with
  `SWIFT_STRICT_CONCURRENCY = complete`. Framework-boundary escape hatches
  (`nonisolated(unsafe)`, `MainActor.assumeIsolated`) must be narrow and carry a comment
  explaining why they're safe. UI packages (`DesignSystem`, `Features/*`) additionally set
  `.defaultIsolation(MainActor.self)` — don't re-annotate `@MainActor` there; infra packages
  (`RadioDirectory`, `Playback`, `Persistence`) keep explicit isolation by design. Prefer
  `isolated deinit` over `nonisolated(unsafe)` state when cleanup needs actor-isolated
  resources.
- **Dependency direction**: `Features/*` → (`Playback`, `Persistence`, `DesignSystem`) →
  `RadioDirectory`. `DesignSystem` stays presentational. `Playback` never imports persistence or
  UI-feature code — cross-cutting effects are wired via hooks in `AppDependencies.bootstrap()`.
- **Dependency injection everywhere**: services take their collaborators via initializers with
  production defaults (`PlaybackController(directory:output:nowPlayingCenter:)`), so tests inject
  fakes. New service seams should follow this pattern.
- **Record significant decisions in `DECISIONS.md`** — a dated entry explaining *why*, not just
  what. Read it before proposing architectural changes; it's the project's memory.
- **Style** is enforced by the checked-in `.swiftformat` and `.swiftlint.yml`. CI runs
  SwiftLint **0.65.0** with `--strict` (warnings fail the build), pinned in `.github/workflows/ci.yml`;
  install that version locally (e.g. `mise use swiftlint@0.65.0`) so your results match CI. CI also
  runs `swiftformat --lint` (currently non-blocking — the tree isn't fully conformant yet, see
  `DECISIONS.md`) — run `swiftformat ShoutKitApp Packages` locally before pushing to help close
  that gap.
- Directory errors are typed (`throws(RadioDirectoryError)`); user-facing failures should carry
  the error, not a bare `String`.

## Localization / String Catalogs

Every package/target with user-facing strings has its own `Localizable.xcstrings` (app, widget,
`DesignSystem`, `RadioDirectory`, and the four feature packages). Most SwiftUI string literals
(`Text`, `Button`, `Label`, `.accessibilityLabel`, etc.) need no special handling — they take
`LocalizedStringKey` and are catalog-extractable automatically. The exceptions are plain-`String`
APIs (e.g. `LocalizedError.errorDescription`), which must be wrapped explicitly:

```swift
String(localized: "Your message.", bundle: .module)
```

`bundle: .module` is required in every package target — without it, lookup falls back to
`Bundle.main` and silently misses that package's catalog.

**A plain `xcodebuild build` does not sync newly-added string literals into the checked-in
`.xcstrings` files** — that catalog-sync behavior only happens inside the Xcode IDE. After adding
new localizable strings, resync every catalog from the command line with the export/import
round-trip:

```sh
xcodebuild -exportLocalizations -project ShoutKitApp/ShoutKitApp.xcodeproj \
  -localizationPath /tmp/shoutkit_locexport -exportLanguage en
xcodebuild -importLocalizations -project ShoutKitApp/ShoutKitApp.xcodeproj \
  -localizationPath /tmp/shoutkit_locexport/en.xcloc
rm -rf /tmp/shoutkit_locexport
```

Then diff the affected `Localizable.xcstrings` files before committing.

## Developer Certificate of Origin (DCO)

Contributions must be signed off:

```sh
git commit -s
```

This adds a `Signed-off-by:` trailer certifying the [Developer Certificate of
Origin](https://developercertificate.org) — that you wrote the change or otherwise have the right
to submit it under the project's licenses. This keeps the project's copyright provenance clean
(which is what makes dual licensing, app-store distribution, and future relicensing possible)
without a heavyweight CLA.

By contributing, you agree your changes are licensed under the license of the component they
touch: GPL-3.0 for the app and feature packages, MIT for `RadioDirectory`, `Playback`,
`Persistence`, and `DesignSystem` (see the Licensing table in the README).

## Pull requests

- Keep PRs focused; separate refactors from behavior changes.
- Add or update tests for anything testable — especially playback state transitions and
  directory parsing/caching.
- CI must pass: app build, host test suites, and lint.
- The ShoutKit name and icon are trademark-reserved (see `TRADEMARK.md`) — forks are welcome and
  must rebrand; contributions here need no special permission.

## Releasing

1. Move the relevant `CHANGELOG.md` entries out of `## [Unreleased]` into a new
   `## [X.Y.Z] — <date>` section.
2. Merge that to `main`, then push a `vX.Y.Z` tag pointing at the merge commit.
3. `.github/workflows/release.yml` drafts a GitHub Release from that CHANGELOG section — review
   and publish it manually. The workflow only drafts release notes; it does not sign or upload a
   build (no Apple signing credentials are configured in this repo yet), so TestFlight/App Store
   distribution is still a separate, manual Xcode Organizer step.

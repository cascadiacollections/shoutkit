# Working in this repository

Orientation for AI agents. Everything here is environment knowledge that is expensive to
rediscover — the human-facing docs are better for everything else, and are listed at the end.

## Read `DECISIONS.md` before proposing an architectural change

It is ~140 KB of dated entries explaining *why*, newest first, and it is the most current
document in the repo — more current than `docs/ROADMAP.md` has historically been. Most
"why is this written this way" questions are answered there, usually with the evidence that
settled it. `CONTRIBUTING.md` requires a new entry for any significant decision, and that
applies to agent-authored changes too.

Search it before concluding something is an oversight. Several things that look like bugs
are recorded deliberate trade-offs (`.normal` having no equalizer curve; the station
artwork never being its own fallback; `onStationPlayed` staying a closure while the other
hooks became `Observations`).

## Building and testing

Two paths, and they cover different code:

```sh
# 1. Mac host — the fast loop. Per package, from its directory.
cd Packages/RadioDirectory && swift test --disable-xctest

# 2. Simulator — the only way to run the iOS-only suites and the app target.
xcodebuild -workspace Holmdel.xcworkspace -scheme Holmdel \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

- **`--disable-xctest` is load-bearing**, not a style choice. Every suite is Swift Testing
  (there is no `import XCTest` anywhere), but `swift test` still runs a legacy XCTest pass,
  and Xcode 27 beta's agent segfaults doing it. Drop the flag only when a stable Xcode 27
  is on the runner image.
- **Only some packages build on the mac host.** Anything depending on `DesignSystem` does
  not. The reason is its manifest: `Packages/DesignSystem/Package.swift` declares
  `.iOS(.v26)` and nothing else, so SwiftPM won't build it for macOS at all. (The sources
  are SwiftUI, not UIKit — 13 files import SwiftUI and 4 import UIKit, all of those for
  `UIImage` in the artwork pipeline. An older version of this note said "UIKit-only", which
  sent people looking in the wrong place.) That single-platform declaration is why
  `BrowseFeatureCore`, `SearchFeatureCore`, and `PlayerFeatureCore` exist: they hold the
  logic that would otherwise be untestable behind a view.
- If `swift test` fails to launch the test binary on a macOS beta, see the `xattr -cr` +
  ad-hoc `codesign` workaround in `CONTRIBUTING.md`.
- If `DEVELOPER_DIR` points at Command Line Tools, prefix commands with
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

## Things that will bite you

- **`swiftlint --strict` is a required check, and warnings are errors.** The two limits that
  actually get hit are `file_length` (400) and `function_body_length` (50, counting neither
  blanks nor comments). `AppDependencies.bootstrap()` in particular has been at the edge
  more than once. **The house remedy is to split along a real seam, not to add a
  `swiftlint:disable`** — see the `+Networking` / `+Factories` / `+Callbacks` / `+Warmups`
  and `PlaybackController+Internals` / `+Recovery` splits.
- **`swiftformat --lint` is currently non-blocking** because most of the tree predates it.
  Don't reformat files you're otherwise not touching; the one-time run is its own task with
  its own workflow (`.github/workflows/format.yml`).
- **The app target is not a SwiftPM package.** New files under `HolmdelApp/` need
  `PBXFileReference`, `PBXBuildFile`, group-child, and Sources entries hand-added to
  `project.pbxproj`. A file that fails to register still builds green — it just silently
  isn't in the binary. Verify the `.o` lands in the build directory.
- **New string literals do not reach the `.xcstrings` catalogs from a command-line build.**
  That sync only happens inside the Xcode IDE. Either run the export/import round-trip in
  `CONTRIBUTING.md` or hand-add the key; the entries are plain JSON. `bundle: .module` is
  required for plain-`String` APIs in package targets.
- **Swift 6 strict concurrency is `complete` everywhere**, and the six UI packages use
  `.defaultIsolation(MainActor.self)`. Infra packages are explicitly isolated instead.
- **A target may only `import` modules its own manifest declares.** Moving a type between
  packages usually means adding an import to every file that names it, not just the one
  that moved.

## Architecture in one pass

`HolmdelApp/` holds thin app, widget, and watch targets; everything else is a local
package under `Packages/`. Dependency wiring goes through Factory, so tests and previews
substitute fakes without touching production call sites.

The rule worth internalizing: **reusable packages are MIT and must not acquire app-specific
or heavyweight dependencies.** That is why Pulse lives in `DebugSupport` and the
AudioStreaming engine lives in `PlaybackEngineAudioStreaming` — both are packages only the
app target links, so `Playback` and friends stay adoptable. If you find yourself adding a
dependency to a reusable package, that is the pattern to reach for.

`Playback` ships no engine at all: `Container.radioPlaybackEngine` resolves to a stub until
`registerProductionPlaybackEngine()` runs in `AppDependencies.bootstrap()`. Break that
ordering and the app builds, launches, and plays silence.

## Verifying your work

CI is `.github/workflows/ci.yml`: host package tests, a simulator test-plan run plus Release
and watchOS builds, and lint. Coverage is collected and reported per package and per target
with no threshold — it is a baseline to watch, not a gate to satisfy.

Prefer a check that can fail over a claim in a commit message. The repo has a habit of this
worth continuing: CI asserts Pulse links into Debug, asserts `Packages/Playback` resolves no
binary artifacts, and inspects the built `.app` for a watch payload. Each exists because
something was believed to be true and turned out not to be.

## Where to look next

| Question | File |
|---|---|
| Why is this built this way? | `DECISIONS.md` |
| How do I build, test, localize, sign off? | `CONTRIBUTING.md` |
| What's next, and what's blocked? | `docs/ROADMAP.md` |
| What shipped, in user-facing terms? | `CHANGELOG.md` |
| What is this project? | `README.md` |

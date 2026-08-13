# Decisions

## 2026-08-13 (artwork traffic gets its own, lower-priority session — it was never actually deprioritized against the stream)

The 2026-08-03 power review (below) gave *speculative* artwork prefetch its own session
(`.background`, refuses constrained/expensive networks) so it would yield to "the directory and
to artwork a visible row actually needs." What it left unexamined: what a visible row, the Now
Playing hero, lock-screen art, and Live Activity art were yielding to. All four defaulted to
`URLSessionHTTPTransport.shared` — the same `.responsiveData` session as directory search — and
`.responsiveData` is a scheduling hint, not a label: on a weak link (LTE, 3G, a saturated Wi-Fi;
"5G or worse" covers the range this matters for) it tells the system this fetch is as
latency-sensitive as anything else marked the same way. The one thing on the device actually
marked that way and genuinely latency-sensitive is the audio stream itself — except it isn't
marked at all. `PlaybackEngineAudioStreaming` hands a URL to AudioStreaming's `AudioPlayer` and
never touches the `URLSession` underneath; that session is entirely internal to the library, so
nothing in this repo can raise the stream's own priority.

The only lever available, then, is to lower artwork's instead. `URLSessionHTTPTransport.artwork`
(`HTTPTransport.swift`) is a new session for exactly the traffic the August review didn't touch:
row thumbnails, hero art, `NowPlayingCenter`/`MediaSessionNowPlayingCenter` lock-screen art, and
`NowPlayingActivityCoordinator`'s Live Activity art. It sets `networkServiceType = .background`
like the speculative session, but — unlike speculative — leaves
`allowsConstrainedNetworkAccess`/`allowsExpensiveNetworkAccess` at their permissive defaults: this
is traffic a listener is actually waiting on (their lock screen, the row they're looking at), not
a look-ahead guess, so Low Data Mode and cellular must not suppress it outright the way they
suppress prefetch. `.background` only asks the scheduler to give it a lower queue position than
whatever else is moving bytes — which in this app is always the stream.

Directory JSON search (`ShoutcastDirectoryClient`, `RadioBrowserDirectoryClient`) stays on
`.shared`/`.responsiveData`: it's a few KB of metadata per keystroke, not a sustained transfer,
and it isn't the traffic this problem is about. `AlbumArtLookup`'s iTunes metadata query is the
same shape and is left alone for the same reason — only the artwork *bytes* it points at, fetched
through `ArtworkLoader`, move to `.artwork`.

## 2026-08-13 (nothing has ever been released: 0.1–0.3 are milestones, `v0.4.0` is the first real release)

The repo has **zero git tags**. `release.yml` is `on: push: tags: v*.*.*` and has never run.
Meanwhile `CHANGELOG.md` carried a dated `[0.1.0]`, a `[0.2.0] — in progress (first TestFlight
beta)`, and a 260-line `[Unreleased]`; `docs/releases/` held plans for 0.2.0 and 0.3.0, the
latter marked "Closed 2026-08-07. Every workstream below shipped"; `docs/ROADMAP.md` said
"0.3.0 is done"; and the project file read `MARKETING_VERSION = 0.2.0`. **There was no
`[0.3.0]` section in the changelog at all**, so pushing `v0.3.0` would have failed on
`release.yml`'s own guard — the pipeline was not merely unused, it could not have worked.

**The decision: 0.1.0–0.3.0 were internal milestones, not releases, and the changelog now says
so.** The alternative was to reconstruct a `[0.3.0]` section by splitting `[Unreleased]` at
the 2026-08-07 close date and retro-tagging it. That was rejected because it documents a
fiction: no build from any of those numbers reached a user, and "released" has to mean a user
could get it or the word stops carrying information. It is the same failure mode as a roadmap
listing shipped work as pending — a record that reads plausibly and is false. The milestone
numbers are kept rather than renumbered because the release-plan docs, `DECISIONS.md`, and
`git log` all reference them; rewriting history to start at 0.1.0 again would break more than
it fixed.

`v0.4.0` continues the sequence rather than claiming 1.0.0. The 1.0 bar — a professional icon,
signing secrets, an App Store listing — is not met, and a first release that overstates itself
is the same error in the other direction.

**A bug found while doing this, worth more than the bookkeeping: the targets disagreed with
each other.** `MARKETING_VERSION` appears twelve times in `project.pbxproj` (there is no
xcconfig for it) and split six/six — the app, widgets, and tests at `0.2.0`; the watch app,
watch widgets, and tvOS app at `0.3.0`. An embedded watch app whose
`CFBundleShortVersionString` differs from its host app's **fails App Store validation**, and
the watch app only became embedded at all in #166 — so this would have surfaced as a rejected
upload on the first real submission, with the embed as the obvious suspect and the version
skew as the actual cause. All twelve now read `0.4.0`.

**What a release currently is, stated plainly because it was not written down anywhere:**
`release.yml` extracts the matching `## [X.Y.Z]` section from `CHANGELOG.md` and opens a
*draft* GitHub Release. It does not sign, archive, upload to TestFlight, or submit. Every
binary that has ever reached a device was built by hand in Xcode. `docs/RELEASING.md` now
records that, along with the steps, the twelve-site version bump, and the gaps still open
(no signing secrets, no build-number increment, no check that the tag matches
`MARKETING_VERSION`).

**Sequencing note.** The changelog cut-over — renaming `[Unreleased]` to `[0.4.0]` — is
deliberately *not* in this change, and is the last step before the tag. Three PRs (#166, #167,
#168) were in flight writing to `[Unreleased]`, and renaming the heading underneath them
guarantees three conflicts for no benefit. `docs/RELEASING.md` documents it as step 1 of the
release itself.

## 2026-08-13 (a privacy manifest per bundle: the watch and tvOS apps had none)

`PrivacyInfo.xcprivacy` existed exactly once, in `ShoutKitApp/ShoutKitApp/`, registered to the
`ShoutKit` target alone. The watch app and the tvOS app — separate bundles, one of them now
embedded inside the iOS app — shipped without one. Both now have their own.

**Why it matters, and why it would not have shown up until the worst moment.** `UserDefaults`
is a required-reason API. Apple's submission check (ITMS-91053, "Missing API declaration")
inspects each bundle in the upload, so an embedded watch app or a separately-submitted tvOS app
needs its own declaration; the host app's does not cover them. Nothing in the build, the tests,
or `swiftlint` looks at this. It surfaces as a rejected or flagged upload on the **first real
submission** — which, since the repo has never released anything (see the entry below), is
still ahead. That makes it the same shape as the `MARKETING_VERSION` skew found the same day:
silent locally, fatal once, and pointing at the wrong culprit when it fires.

**The two targets are declared for different reasons, and the tvOS one is worth stating
plainly:**

- **watch app** — a direct call. `WatchAppDependencies` holds a `UserDefaults.standard` and
  stores the last-played station under `Keys.lastStation` so the "Play Last" complication can
  render and act without the phone.
- **tvOS app** — *no tvOS source touches `UserDefaults` at all.* `TVAppDependencies` goes
  through `Persistence`'s `LibraryStore`, which is SwiftData. But `Persistence` is statically
  linked into the tvOS binary and its `SettingsStore`/`DefaultsKey` do call `UserDefaults`, and
  Apple's check is **symbol-based rather than reachability-based**. Declaring it is therefore
  correct even though the path may never run. The alternative — omitting it and arguing
  reachability with App Review — is not a trade worth making for four lines of plist.

**Deliberately not added: manifests for the widget extensions.** `ShoutKitWidgets` and
`ShoutKitWatchWidgets` import only SwiftUI and WidgetKit, and reach app data through
`QuickPlayFavoritesStore`, which is file I/O in the App Group container — writing and reading
files is not a required-reason category, and neither extension touches `UserDefaults`. Adding
empty manifests there would be cargo-culting. If either extension later reads file timestamps
or disk space, that changes and the manifest becomes required.

**Verified against the built products, not the project file**, because a resource that fails to
register still builds green — the same trap as the source-file registration noted on 2026-08-12
and the watch embed itself. Both `ShoutKitWatchApp.app` and `ShoutKitTVApp.app` were built and
inspected for `PrivacyInfo.xcprivacy` in the bundle root.

Also checked and *not* a gap: the iOS app's existing manifest. It declares
`NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` and nothing else, and a sweep
for file-timestamp and disk-space APIs across every package and app target found only
`setResourceValues(isExcludedFromBackup:)` in `DirectoryDiscoverySnapshot`, which is not a
required-reason category. The declaration is accurate as written.

## 2026-08-13 (`recommendations` is deleted — the only one of the five that was actually deletable)

`RecommendationService` is gone: 193 lines of source, 127 of tests, the `FeatureCatalog`
entry, the "More Like This" section in `ListenNowView`, and two localized strings. This
resolves the second of #146's five, and it is the *only* one the audit found could be removed
without touching a shipping feature.

**Why delete rather than promote.** It had been built, tested, and wired for months with a
live call site, and no user had ever seen it. Promoting it would mean deciding that
content-based station similarity is a feature ShoutKit wants to stand behind — its quality
tuned, its empty state designed, its results defensible — and nobody has made that case. The
carrying cost was real and ongoing: it kept `Accelerate` and a 40-line FNV-1a hashing utility
alive, and it added two parameters to a public `ListenNowView` initializer that no caller ever
passed. Deleting is reversible through git; carrying dead code is not free.

**What made this one clean, when three of its siblings are not.** Every reference resolved to
either the feature itself or its single call site — verified by tracing, not by counting
files, which is the discipline the entry below had to learn twice. `ListenNowView` was the
only consumer, and `RootView.swift:127` constructs it as `ListenNowView(viewModel:)` without
either injected dependency, so removing both parameters changed no call site.

**Two things removed that were not obviously part of the feature:**

- **`BrowseFeature` no longer depends on `FeatureFlags` at all** — target *and* package
  dependency. `ListenNowView` was the package's only `FeatureFlags` consumer, and it only
  used it to ask whether recommendations were on. A discovery surface that no longer asks any
  feature-flag question should not link the module that answers them.
- **`RecommendationHashing`** went with it. It was `public` and looked like general-purpose
  infrastructure, but the only caller outside `RecommendationService` was the recommendation
  cache key in `ListenNowView`. If a stable cross-process FNV-1a is wanted later it is four
  lines, and `git log` has this one.

**One thing deliberately kept.** `LibraryStore.hideFromListenNow` stays a *soft* hide even
though its stated reason was that "the play record stays intact so recommendations still learn
from it." The behaviour is still correct — dismissing a card from the Listen Now teaser is not
"forget I played this," and the record still feeds the Library's Recently Played list and
`rankedStations`, which drives CarPlay and the quick-play widget — so the comments were
rewritten to the reason that survives rather than deleted along with the feature. A comment
whose justification has been removed is worse than no comment: it is a live claim about why
the code is shaped this way, and it would have been false.

## 2026-08-13 (`diagnostics` stays internal-only, permanently, and that is the decision — not a deferral)

`docs/ROADMAP.md` lists five features sitting at `internalOnly` / `defaultEnabled: false` in
`FeatureCatalog` and asks each to be **promoted or deleted** (#146), on the correct principle
that unshipped inventory is not a backlog — it is code that must keep compiling, keep passing
tests, and keep being reasoned about during refactors. It also allows that `diagnostics` is
"arguably correct as internal-only forever, but say so." This says so, and closes that fourth
of #146. It is a third answer to promote-or-delete, and it is only legitimate *stated*: an
undecided flag and a permanently-internal one look identical in the catalog, which is how the
first becomes the second by neglect.

**Measured first, because the roadmap's framing understates this one.** `diagnostics` is
**1,087 lines** across `DiagnosticsMetricSummary` (422), `DiagnosticsService` (213),
`DiagnosticsPayloadStore` (146), `Container+Diagnostics` (18), and 288 lines of tests. The
whole dark inventory is roughly 2,050 lines, so this single feature is **over half of it** —
more than `recommendations` (320), `prewarmStations` (304), and the `geoStations` coordinator
(173) combined. Whatever is decided about the other four, this is the one that dominates the
carrying cost.

**Why it stays rather than ships.** It is a developer instrument, not a user feature. It
subscribes to MetricKit, persists `MXMetricPayload`/`MXDiagnosticPayload` blobs to a local
GRDB store with 30-day retention, and logs summaries. A user toggling it on gets no screen,
no number, and no benefit — the value accrues to whoever reads the log while debugging.
Promoting it would mean building the surface that makes it worth a user's attention, which is
a feature nobody has asked for; deleting it would throw away the instrument that makes a
launch-time or memory regression diagnosable, right as #148 proposes capturing exactly those
baselines per build.

**Why it stays rather than gets deleted, stated as a privacy question**, because that is the
form the objection takes for anything named "diagnostics": it is double-gated on
`featureFlags.isEnabled(diagnostics) && settings.isDiagnosticsSharingEnabled`
(`DiagnosticsService.swift:91`), both false by default, and **there is no network egress
anywhere in it** — no `URLSession`, no upload path, nothing. The data is on the device and
stays there. "Sharing" in the settings key is a misnomer worth correcting whenever that
string is next touched; nothing is shared with anyone.

**Two things this audit turned up that are not resolved here**, recorded so they are not
rediscovered:

1. **`DiagnosticsMetricSummary` (422 lines — 39% of the feature) has no consumer outside
   `Persistence`.** Nothing reads `metricPayloadSummaries(limit:)`; the summaries go to
   `OSLog` and stop. So the largest single file in the feature exists to format text nobody
   retrieves programmatically. That is a genuine deletion candidate *even though the feature
   stays*, and it is a separate decision from this one — it needs someone to confirm the
   OSLog output is actually what gets read during a debugging session, which is a claim about
   practice, not code.
2. **Three of the five are not cleanly deletable, contrary to the roadmap's framing of all
   five as equivalent** — and the general lesson is that **a line count next to a flag is not
   a deletion estimate**. What a flag gates is routinely smaller than the code it names,
   because the code gets reused by something that ships:

   - **`geoStations`** — region identity is threaded into the *shipping* caching layer
     (`CachingRadioDirectory.swift:195`, `DirectoryDiscoverySnapshot.swift:40`), stamping and
     invalidating snapshots by region for every user today. Only the 173-line
     `GeoStationLocationCoordinator` and the flag are dark. Scope it as "delete the opt-in
     precise-location path," not "delete geo."
   - **`prewarmStations`** — `StationConnectionPrewarmer` (133 lines) is called by
     `WarmupRadioAudioQueueIntent` (`ShoutKitAudioIntents.swift:82`), a shipping App Intent
     with **no flag gate**, so deleting the flag leaves the prewarmer in place and still used.
     `LibraryStore+Prewarm.swift` (123 lines) is mostly not prewarm either —
     `rankedStations(limit:)` drives CarPlay (`ShoutKitCarPlaySceneDelegate.swift:106`),
     alongside `favoriteStations()`, `mostRecentStation()`, and `refreshStreamURLSnapshot()`.
     The dark surface is the flag, the launch-warmup block, `prewarmStreamURLs(limit:)`, and
     the `tapToAudioPrewarmEnabledProvider` wiring, which only labels a log line in
     `TapToAudioLatencyTrace`.
   - **`liveActivity`** — `NowPlayingActivityCore` is linked by the shipped quick-play Home
     Screen widget (`QuickPlayWidget.swift:34` uses `QuickPlayFavoritesStore`), so deleting
     the feature removes `NowPlayingLiveActivity.swift` and the artwork store while the
     package stays.

   That leaves **`recommendations` as the only one of the five that is cleanly deletable**:
   one call site, self-contained in `RadioDirectory`.

## 2026-08-12 (the watch app ships: a companion key, an embed phase, and the warning becomes a check)

The watchOS companion recorded here on 2026-07-16, advertised in `README.md`, and compiled by
CI since PR #138 has **never installed on anyone's watch**. It built, it passed, and it was
not in the product. `ShoutKit.app` had no `Watch/` payload; `ShoutKitWatchApp` was a sibling
top-level target reachable only from its own scheme.

**The root cause was one missing Info.plist key, not the missing copy phase.**
`ShoutKitWatchApp/Info.plist` declared `WKApplication` and stopped there, which describes a
*standalone* watch app — one distributed on its own, with no phone app to attach to. The
bundle id was already `com.cascadiacollections.shoutkit.watch`, a correct suffix of the phone's
`com.cascadiacollections.shoutkit` (`Config/{Debug,Release}.xcconfig`), so the intent was
plainly a companion; nothing ever told the installer that. `WKCompanionAppBundleIdentifier` is
now set. It is hardcoded rather than derived because `PRODUCT_BUNDLE_IDENTIFIER` inside the
watch target's own plist would expand to the *watch's* id; `Beta.xcconfig` only adds
`OTHER_SWIFT_FLAGS`, so there is no configuration in which the phone id differs.

The embed itself is the ordinary five objects added to `project.pbxproj` by hand — a
`PBXBuildFile` for `ShoutKitWatchApp.app`, a `PBXContainerItemProxy` and `PBXTargetDependency`
so the watch target builds first, and a `PBXCopyFilesBuildPhase` with
`dstSubfolderSpec = 16` / `dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`, wired into `ShoutKit`'s
`buildPhases` and `dependencies`.

**Hand-editing the pbxproj is the thing `CLAUDE.md` warns about, so the edit was checked
against a real build rather than trusted.** `xcodebuild … -destination id=<iPhone 17>` now
produces `ShoutKit.app/Watch/ShoutKitWatchApp.app`, whose Mach-O reports
`platform WATCHOSSIMULATOR / minos 26.0`, whose `WKCompanionAppBundleIdentifier` reads back as
the phone id, and which carries `PlugIns/ShoutKitWatchWidgets.appex` (the "Play Last"
complication) with it. That last detail is the one worth noting: nothing separately embeds
the complication into the phone app, because it rides inside the watch app, which is why its
absence was invisible for a month.

**The CI step that found this stops being a diagnostic.** It was added deliberately
non-failing, because it was asserting something the tree did not yet satisfy — the honest
shape for a check written before its fix. It now fails the build, and it additionally asserts
the embedded bundle's `WKCompanionAppBundleIdentifier`. Checking for the copy phase in
`project.pbxproj` would have been the cheaper check and the wrong one: a phase with a wrong
`dstPath` copies the bundle somewhere the installer ignores, producing a green build and no
companion — the same failure with a different cause. The check inspects the built bundle for
the same reason it caught the bug in the first place.

**Not verified, and deliberately left open:** that the companion actually *installs* and pairs.
That needs a paired iPhone + Apple Watch simulator or real hardware, not a build product
inspection. The payload is present, correctly built for watchOS, and correctly keyed; whether
watchOS accepts it at install time is the next thing to confirm, and it belongs on the same
list as the on-device AVRCP verification (#147) — checks that need hardware, not a commit.
Reproduce the bundle-level check with:

```sh
xcodebuild -workspace ShoutKit.xcworkspace -scheme ShoutKit -configuration Debug \
  -destination 'id=<an iPhone simulator udid>' -derivedDataPath DerivedData build
ls DerivedData/Build/Products/Debug-iphonesimulator/ShoutKit.app/Watch
```

Note for anyone re-running it: `-destination 'platform=iOS Simulator,name=iPhone 17'` fails on
a machine with two simulators of that name. Use `id=`.

## 2026-08-12 (tvOS takes the iOS engine: `AudioStreamingPlaybackEngine` replaces AVPlayer, and the TV gets track titles)

The tvOS MVP shipped with `TVRadioPlaybackEngine`, an `AVPlayer` fork of the watch engine, and
the entry below records the known cost: **no ICY metadata**, so a 10-foot display showed the
station and its artwork but never the track. That entry also named the upgrade path and said the
fix would be switching engines rather than patching around it. This is that switch.
`ShoutKitTVApp` now links `PlaybackEngineAudioStreaming` and injects
`AudioStreamingPlaybackEngine` — the same engine the phone runs — and
`TVRadioPlaybackEngine.swift` is deleted rather than left as a fallback.

**What the deferral was protecting against, and why it no longer applies.** The MVP's argument
was not that tvOS was unsupported; it was that binary-artifact resolution on an unproven platform
was a risk not worth taking for v1. That risk is now measured rather than estimated. Re-checked at
the exact revisions pinned in `Package.resolved`, and in the downloaded artifacts rather than the
manifests that describe them:

- `ogg.xcframework` 0.1.2 and `vorbis.xcframework` 0.1.2 each carry a real `tvos-arm64` slice
  *and* a `tvos-arm64_x86_64-simulator` slice (`Info.plist`, `LibraryIdentifier`).
- AudioStreaming 1.4.4 declares `.tvOS(.v16)`.

That is the whole difference from watchOS, which has no slice at all and is why
`Packages/PlaybackEngineAudioStreaming/Package.swift` still omits `.watchOS` — the omission is
load-bearing, the `.tvOS(.v26)` addition is not a loosening of it. The watch keeps
`WatchRadioPlaybackEngine` and there is no version of this change that includes it.

**Verifying the slices, not the manifests, is the point.** A `binaryTarget`'s platform support is
a property of the zip, not of the `platforms:` list in the package that fetches it, and the two can
disagree — the failure mode is a link error naming a missing architecture, which reads as a
toolchain problem rather than a dependency one (#123 is the recorded instance of exactly that, in
the other direction). Reading `LibraryIdentifier` out of each `Info.plist` is a check that can
fail; a manifest's platform list is a claim.

**What the TV gains.** Live track titles, via the one ICY seam in
`audioPlayerDidReadMetadata` — `TVRootView`'s subtitle line and `TVNowPlayingCenter`'s
`MPMediaItemPropertyTitle`/`Artist` were already written to prefer `nowPlaying` and fall back to
the station, so they light up with no change beyond a corrected comment. It also inherits, for
free, everything that has accumulated in the shared engine and could never have been ported
twice: the session-activation retry backoff, media-services-reset recovery, the
`.endOfStream`/`.failed` classification with its 250 ms grace period (the entry directly below),
and the equalizer attach point. The last one is latent — `supportsEqualizer` is now `true` on
tvOS, but there is no Settings surface on this platform, so the preset stays `.normal` until one
exists. That is a seam waiting, not a feature claimed.

**Factory is still bypassed, and that part is not up for revision.** Sharing the engine is not the
same as sharing the wiring. `TVAppDependencies` keeps calling `PlaybackController`'s *designated*
initializer with every collaborator explicit and still does not call
`registerProductionPlaybackEngine()` — the engine is constructed and injected directly. The
`os(iOS)` gates recorded below exist precisely so a second UIKit platform cannot inherit an
initializer that resolves `StubRadioPlaybackEngine` and plays silence, and linking the engine
package is exactly the moment that inheritance would start looking convenient.

**The link is four hand-added `project.pbxproj` entries**, because the app targets are not SwiftPM
packages: an `XCSwiftPackageProductDependency` pointing at the existing
`XCLocalSwiftPackageReference` (the iOS app already declares it, so no new package reference), a
`PBXBuildFile` wrapping it, and one line each in the TV target's `packageProductDependencies` and
its `PBXFrameworksBuildPhase`. The deleted engine's four entries came out in the same pass. A
missing registration compiles green while silently not being in the binary, so the same
after-the-fact inspection the MVP used was run on the built `.app`, and it is worth recording what
it actually proves:

- The four remaining TV sources each produce a `.o` (`ShoutKitTVApp`, `TVAppDependencies`,
  `TVNowPlayingCenter`, `TVRootView`) and `TVRadioPlaybackEngine.o` is gone — the file was deleted,
  not merely orphaned from the target.
- `otool -L` on the app binary lists `@rpath/ogg.framework/ogg` and `@rpath/vorbis.framework/vorbis`,
  and `vtool -show-build` on the embedded `ogg` reports `platform TVOSSIMULATOR`. The codec chain
  did not merely resolve; a tvOS slice linked and embedded.
- `nm` finds both `AudioStreamingPlaybackEngine` and AudioStreaming's `AudioPlayer` in the binary.

The link check is the one that mattered: a `binaryTarget` whose zip lacked the slice would have
failed here, after resolution reported success.

**And a third thing that builds green while being broken, found by running it.** Every check above
passed and the app still died at launch, on the device and in the simulator alike:

```
Termination Reason: DYLD, Code 1, Library missing
Library not loaded: @rpath/ogg.framework/ogg
  tried: '…/ShoutKitTVApp.app/ogg.framework/ogg' (no such file)
```

The frameworks were embedded correctly at `.app/Frameworks/`. What was missing was the *runpath*:
the hand-written tvOS target had no `LD_RUNPATH_SEARCH_PATHS`, so its only rpath entries were
`@loader_path` and a build-directory path, and dyld looked for `ogg.framework` beside the
executable rather than in `Frameworks/`. Note what the failing path says — it is not "cannot find
the library" in the abstract, it is "looked in the wrong directory."

This is a latent defect the MVP could not have surfaced. Xcode adds
`@executable_path/Frameworks` when *it* creates an app target; this one was assembled by hand in
`project.pbxproj`, and every dependency it linked was a static SwiftPM library, so the missing
setting cost nothing. Linking this package introduced the target's first *dynamic* frameworks and
the omission became fatal immediately. Both the Debug and Release configurations now carry the
setting, matching `ShoutKitApp`'s.

**The lesson for the checklist is that the existing checks were all static.** `.o` files, `otool -L`,
`vtool`, `nm`, and a green compile together prove the binary was *built* right; not one of them
runs it, and dyld failures live entirely in the gap between linking and launching. The tvOS job in
`release-checks` compiles and would have stayed green. A launch check — install to a booted tvOS
simulator and confirm the process is still alive a few seconds later — is the cheap check that
would have caught this, and it is the one worth adding when this target next gets CI attention.

**The cost side, stated plainly.** The tvOS app is now heavier than the AVPlayer version — it pulls
the C codec stack and its own `AVAudioEngine` graph where before it used the system player — and it
picks up a dependency chain that can break on a tvOS-specific slice regression upstream. The tvOS
compile lives in `release-checks` (push-to-main and `workflow_dispatch`), not on every PR, so a
regression there surfaces on `main`. That trade was accepted for the MVP's own reasons and is
unchanged by this; it is worth restating because the blast radius of a tvOS build failure just grew
from "our five files" to "our five files plus a binary dependency chain".

## 2026-08-12 (a finished broadcast is not a dropped stream: `.endOfStream`, and looping as opt-in)

Stations that broadcast a **fixed-length programme** — NPR's hourly newscast is the reported
case — played through and then started over, up to four times, before the app gave up. The
stream itself was fine; the bug was in what "the stream stopped" was taken to mean.

`AudioStreamingPlaybackEngine` reported end-of-stream as `.failed(.streamFailed(…))`, which was
right for the case it was written for (2026-05-14: a live stream the server closes stops the
player with no error, and swallowing it left a dead stream showing as playing). The controller
does the sensible thing with a retryable failure and calls `attemptReconnect`, and a reconnect
for live radio is a fresh `startPlayback` — so a *finite* programme was rejoined from the top
once per attempt in the budget. The reconnect wasn't misbehaving; it was being handed the wrong
verdict.

**The fix is a third verdict, not a tuned reconnect.** `AudioStatus.endOfStream` sits alongside
`.failed`, and `PlaybackController.handleEndOfStream` parks the station as `.paused` with the
player torn down — the lock screen and mini-player stay put, and play replays the programme
through the existing `outputStarted == false` restart path. Same shape as the stall ceiling's
give-up (2026-05-27), and for the same reason: reaching the end of a broadcast is not a user
error, so a `.failed` screen would be a lie.

**Only the engine can tell the two endings apart, and only from one callback.** AudioStreaming's
`.stopped` transition carries nothing that distinguishes them; the pair that does is
`audioPlayerDidFinishPlaying`'s `progress`/`duration`. `duration` is `0` for live audio (it can
only be derived from a known content length), so an endless stream never qualifies however it
ends, and a finite one truncated mid-download doesn't either — its duration is the whole
programme's while its progress is where the bytes stopped, which is a genuine drop worth
reconnecting for. The tolerance around the comparison (3s or 2%, whichever is larger) is there
because both numbers come from an estimated bitrate and rarely agree exactly; a strict compare
would reinstate the bug on any file whose estimate ran long.

**The ordering that made this awkward, from reading AudioStreaming 1.4.4:** the `.stopped` state
change is dispatched to the main queue from inside `processSource()`, and `didFinishPlaying` is
dispatched *after* it, from the same source-queue block. So the stop always arrives first, with
no way to classify it yet. Rather than decide wrongly, `handleUnexpectedStop` leaves the stop
unattributed for a 250 ms grace period; `reportEndOfStream()` cancels that task if the finish
callback claims the ending, and otherwise it becomes the retryable failure it always was. The
cost is 250 ms of added latency before a reconnect for a genuinely dropped stream, which is
inside the backoff's own first delay. This is a grace period, not a poll — it only has to
outlast a main-queue hop, and both re-checks (`didRequestStop`, `player.state`) still run when
it fires.

**Looping is opt-in, and off by default.** `SettingsStore.isStreamLoopingEnabled` (Settings →
Playback → "Loop Finished Broadcasts") flips the ending from "stop" to "start over". Default off:
a broadcast with an end means to end, and repeating it is a listener's choice, not a player's
guess. The controller reads it through `isStreamLoopingEnabledProvider` at each ending rather
than capturing it at `play()`, so flipping the toggle applies to the programme already playing —
and `Playback` keeps knowing nothing about `Persistence`, same seam as
`tapToAudioPrewarmEnabledProvider` and `trackResourcesProvider`. The loop restart is an
*internal* restart (`isReconnect: true`): the resolved endpoint is reused and `onStationPlayed`
stays silent, so a loop can't log one listening session as many recents or many Radio-Browser
play reports.

**The AVPlayer engines get the same signal.** watchOS and tvOS reported a finished item as a
plain `.paused` (a stop with `currentItem` still set), which happened to look right and was
indistinguishable from a user pause — so it could never be looped. Both now observe
`AVPlayerItemDidPlayToEndTime` and report `.endOfStream`; a live stream on those engines drops
through `AVPlayerItemFailedToPlayToEndTime` instead, which stays a failure. Neither app has a
settings surface, so both take the default and stop, exactly as they did before.

## 2026-08-12 (tvOS MVP: the watch app is the blueprint, and AVPlayer is the engine)

ShoutKit gets a fourth platform. `ShoutKitTVApp` is a top-level target — five files, three
linked packages (`RadioDirectory`, `Playback`, `Persistence`), bundle id
`com.cascadiacollections.shoutkit.tv`, tvOS 26.0 floor.

**The blueprint is `ShoutKitWatchApp`, not `ShoutKitApp`.** The watch app is the working
precedent for a second platform reusing the shared packages with its own minimal service
graph: it calls `PlaybackController`'s *designated* initializer with every collaborator
explicit and bypasses Factory entirely, so it never touches
`registerProductionPlaybackEngine()`. `TVAppDependencies` copies that exactly. The phone app's
`Features/*` and `DesignSystem` are deliberately **not** linked — the focus engine changes the
whole layout model, so a touch-idiom view hierarchy would have to be fought rather than reused,
and the watch established that skipping them is viable. `LiveActivity` (ActivityKit, iOS-only)
and `DebugSupport` (Pulse) stay off for the reasons they are separate packages at all.

A new platform only has to implement `AudioOutput` — four methods and two callbacks —
because `PlaybackController` itself is portable (Foundation + Observation + RadioDirectory).
`RadioPlaybackEngine`'s equalizer members have defaults, so an AVPlayer engine inherits
"no EQ" for free.

**AVPlayer over AudioStreaming, and the ICY cost.** Checked at the exact tags in
`Package.resolved`, tvOS *is* supported by the whole streaming chain — AudioStreaming 1.4.4
declares `.tvOS(.v16)`, and both the ogg and vorbis xcframeworks declare `.tvOS(.v15)`. So
unlike watchOS, which genuinely has no slice, `PlaybackEngineAudioStreaming` **could** ship
here. It is deferred to v2 anyway: AVPlayer is the established doctrine (2026-07-16), it is
proven twice in this repo, and it keeps binary-artifact resolution off an unproven platform.

The price is paid knowingly and is worth restating because it is user-visible: **the AVPlayer
engine emits no ICY metadata**, so the TV shows station name, genre, and artwork but never the
current track. On a 10-foot display that absence is more noticeable than on a watch. If live
track titles turn out to be must-have, the fix is switching to AudioStreaming, not patching
around it — the dependency chain already supports it.

`TVNowPlayingCenter` is a *real* `NowPlayingPresenting`, unlike the watch's no-op: tvOS shows
artwork, so the station favicon is fetched and attached. It is a separate type from
`Playback`'s `NowPlayingCenter` (now `os(iOS)`-gated, see below) because that one carries the
lock-screen contract and a Bluetooth/AVRCP artwork-resizing path with no meaning on a TV.

**Two things that build green while being broken**, both now checked rather than trusted:

1. A source file missing its `project.pbxproj` registration compiles green and silently isn't
   in the binary. Verified by confirming all five `.o` files land in the build directory.
2. **actool reports a malformed layered app icon and still exits zero.** The first build of
   this target printed `** BUILD SUCCEEDED **` alongside `The image stack "App Icon" must have
   at least 2 layers with applicable content` — a green build with an icon that would fail at
   install or App Store validation. CI now greps the tvOS build log for asset-catalog errors
   and fails on them, because the compiler's exit code will not.

The tvOS build sits in `release-checks` (push-to-main and `workflow_dispatch` only), not on
every PR: `xcode-27` is a billed larger runner and that job was just restructured to cut spend
~70%. Same accepted trade as the Release and watchOS compiles it joins — tvOS breakage surfaces
on `main` rather than on the PR, in exchange for not paying for a third compile per push.

Signing note for anyone reproducing this: `generic/platform=tvOS` fails with "your team has no
devices from which to generate a provisioning profile". A tvOS profile requires a *registered*
Apple TV, so the first build must target a paired device by `id=` — that registers it and mints
the profile. CI therefore builds tvOS with `CODE_SIGNING_ALLOWED=NO`.

## 2026-08-12 (platform gates say what they mean: `os(iOS)`, not "UIKit and not watch")

Two `#if` gates in `Packages/Playback` were spelled `canImport(UIKit) && !os(watchOS)` and
meant `os(iOS)`. Both are now `os(iOS)`:

- `PlaybackControllerPlatform.swift:1` — the `PlaybackController.init(directory:)` convenience
  initializer plus `makeSystemNowPlayingCenter()`.
- `NowPlayingCenter.swift:38` — the `MPNowPlayingInfoCenter` bridge.

The UIKit spelling is true on **tvOS and visionOS as well as iOS**, and the difference is not
cosmetic. `init(directory:)` resolves the engine through `Container.shared.radioPlaybackEngine()`,
which is `StubRadioPlaybackEngine` until `registerProductionPlaybackEngine()` runs. Any future
UIKit platform target would therefore have silently inherited an initializer that compiles,
links, launches, and **plays silence** — the exact failure `CLAUDE.md` calls out for engine
registration ordering, arriving by inheritance rather than by a missed call. `NowPlayingCenter`
would likewise have come along with its `UIImage`/`UIGraphicsImageRenderer` artwork path onto a
platform wanting its own now-playing surface.

The seam that makes narrowing safe already existed: `NowPlayingPresenting` is ungated, and the
watch app is the working precedent for a second platform calling `PlaybackController`'s
*designated* initializer with explicit collaborators and bypassing Factory entirely
(`WatchAppDependencies.swift`). **A new platform should have to write its wiring, not inherit
iOS's.** These gates now enforce that rather than leaving it to whoever notices.

Availability wildcards were tightened in the same pass, for the reason recorded below on
2026-08-12: a bare `*` means "available from *this* platform's deployment target", so it is
correct only by coincidence and goes wrong the moment a platform exists at a floor beneath what
the symbols require. That already cost a broken watch build once. Both `NowPlaying` sites now
name tvOS explicitly — `MediaSessionNowPlayingCenter`'s `@available` (gated only on
`canImport(NowPlaying)`, so it compiles on any platform that has the framework) and the
`#available` check that selects it.

No behaviour changes on any shipping platform: iOS and Mac Catalyst are inside `os(iOS)`, and
watchOS was excluded before and after. Verified locally — `swiftlint --strict` clean, the
`Playback` host suite, the iOS Simulator build, and the watchOS compile check all green.

## 2026-08-12 (the marketing page gets a face, and an og-image that isn't a guess)

The `site/` one-pager was a competent dark/indigo template. It said the right things but looked
like every other developer landing page, and it was missing the parts that make a page findable:
no canonical URL, no `og:image`, no structured data, no `robots.txt`, no sitemap. A social share
rendered as a bare text link.

The rewrite is a warm, low-sun palette — sand ground, sunset gradient, teal for links — with the
boldness spent in exactly one place: a sunset panel that keeps its own colours in *both* themes,
so the accent never washes out on a light ground. Everything else reads from tokens defined three
times (bare `:root`, `prefers-color-scheme` guarded by `:not([data-theme="light"])`, and an
explicit `[data-theme="dark"]` stamp), which is what makes an unstamped "system" viewer resolve
correctly. The recurring structural device is a tuning-dial rule, because the subject is a radio.

**No webfont, deliberately.** The obvious move for a warmer page is a display face from a font
CDN. A page whose central claim is "this app tracks nothing" should not open a connection to
Google on load, so the type is built from `ui-rounded` / `ui-sans-serif` / `ui-mono` system
stacks. The page is still one file with zero subresources, which is also the fastest thing it
could possibly be.

**The social card is generated, not hand-drawn.** `site/og-image.html` renders to
`site/og-image.png` with a headless Chromium screenshot at 1200×630, so the card can be
regenerated after a copy change without a design tool. One trap worth recording: full Chrome
reserves part of `--window-size` for browser UI and letterboxes the shot — the bottom of the card
came out clipped and the difference is invisible until you look at the PNG. Chromium's
`headless_shell` sizes the viewport exactly. The command and the caveat are in a comment at the
top of the generator.

SEO additions are the ordinary set, and they are ordinary on purpose: canonical, `og:`/`twitter:`
tags pointing at the generated card, a JSON-LD `@graph` (`WebSite`, `SoftwareApplication`,
`FAQPage`), `robots.txt`, `sitemap.xml`, one `<h1>`, semantic landmarks, and a skip link. The
FAQ copy and the JSON-LD `FAQPage` are written from the same answers — if one changes, both have
to, which is the cost of having them at all.

Content moved toward the free-software story the project actually has: the two-licence split and
*why* it exists, a three-command build, where to contribute, and credit to Radio-Browser as the
upstream that makes keyless discovery possible. No App Store link, because there isn't one — the
primary CTA is the source.

## 2026-08-12 (the deployment floor drops to iOS 26)

Minimum iOS/iPadOS and watchOS go from 27.0 to **26.0**. iOS 27 is still in beta; requiring it
meant the shipping app could only be installed by people running a beta OS, which is not a
supportable position for a public release. iOS 26 is the current shipping release and becomes
N-1 when 27 goes GA.

Devices already on the iOS 27 beta are unaffected, and this is worth being explicit about
because it is the part people get backwards: a *lower* deployment target does not drop newer
systems. iOS 27 runs an iOS 26-targeted build exactly as before, and the iOS 27-only code path
still activates there at runtime. The floor is a minimum, not a target.

**The surprise: nothing had to be back-ported.** The expectation going in was that lowering the
floor would mean an availability-gating pass. It did not — the repository contains exactly two
availability annotations, and both already gate the only iOS 27-only API in the tree:

- `Packages/Playback/Sources/Playback/MediaSessionNowPlayingCenter.swift:28` —
  `@available(iOS 27, macOS 27, *)` on the type.
- `Packages/Playback/Sources/Playback/PlaybackControllerPlatform.swift:39` —
  `if #available(iOS 27, *)` selecting it, with `NowPlayingCenter` (the
  `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` bridge) as the unconditional fallback.

That selection was built in the 2026-07-13 pass *because* MediaSession was a first-beta
framework worth being able to back out of. The iOS 26 path was therefore written, wired, and
kept working the whole time — the floor was simply set higher than any code required. So this
change is version numbers, not behaviour: 17 `Package.swift` manifests, 8 build settings in
`project.pbxproj`, and the two `.xcconfig` files.

The `.xcconfig` pair is the trap worth recording. `ShoutKitApp/Config/Debug.xcconfig` and
`Release.xcconfig` each set `IPHONEOS_DEPLOYMENT_TARGET`, and they are the app target's
`baseConfigurationReference`, so they *override* the project-level value in `project.pbxproj`.
Editing only the pbxproj — which is where you would look — leaves the app itself on the old
floor while every package moves, and nothing fails to build to tell you.

What did **not** change: the toolchain. The manifests are still `swift-tools-version: 6.4` and
the MediaSession path still needs the iOS 27 SDK to compile, so Xcode 27 and the billed
`xcode-27` runner remain required. Deployment target and toolchain are independent, and
lowering one does not lower the other — see the 2026-08-11 CI entry for why that distinction
has money attached to it.

## 2026-08-12 (RadioBrowserDirectoryClient splits; `main` is lint-clean again)

`RadioBrowserDirectoryClient.swift` went 398 → 445 lines when the search filters landed in
#157, crossing SwiftLint's 400-line `file_length` limit that `--strict` promotes to an
error. `main` had been lint-red since that merge, and once `lint` became a gate (2026-08-11)
that one violation was skipping every test job in the repository — no host tests, no
simulator run, no `release-checks`, on any branch.

Split along three seams rather than suppressed, per the standing house rule:

- **`+Mapping`** — the five `static` DTO→`Station` translators. The cleanest of the three:
  no actor state, no I/O, already `static`, and it was the largest single block in the type.
- **`+Filters`** — `StationSearchFilters.radioBrowserQueryItems`, the query-parameter
  encoding added by #157. `private` became internal now that it no longer shares a file with
  its only caller.
- **`RadioBrowserWireTypes`** — the `Decodable` wire structs, which were never part of the
  client at all, only adjacent to it.

The client drops 445 → 306 lines. The load-bearing detail is that this also let the
`// swiftlint:disable type_body_length` at the top of the file go: the actor body was 288
effective lines, over the 250 warning threshold, and moving `+Mapping` out takes it to 231.
That matters in both directions — had the split landed while leaving the disable in place,
`superfluous_disable_command` would have failed `--strict` just as surely as the original
violation did. A suppression that stops being necessary is itself a lint error here, so
splitting and un-suppressing are one change, not two.

Worth noting for the next person who hits this: the limits are not on raw line count.
`file_length` counts every line, `type_body_length` counts only non-blank non-comment lines
inside the braces. This file is comment-dense, which is why it could be 445 raw lines with a
288-line body, and why "shorten the file" and "shorten the type" are different jobs.

## 2026-08-12 (CodeQL becomes a scheduled scan; the matrix `if` that broke it)

Two things, one of which was a self-inflicted outage.

**The bug.** The 2026-08-11 entry below describes excluding the Swift analysis from pull
requests with a job-level `if: matrix.language != 'swift' || …`. That expression is invalid:
`jobs.<job_id>.if` is evaluated *before* the matrix is expanded, so the `matrix` context is
not available to it — only `github`, `needs`, `vars`, and `inputs` are. A workflow that
references an unavailable context there does not skip the job, it fails to load: zero jobs,
an instant red X, and a run titled `.github/workflows/codeql.yml` instead of `CodeQL`,
because there is no parsed workflow to take a name from. CodeQL ran **not at all** —
neither language — from 21285a9 until this fix.

The reason it survived review is worth recording, because the tell was there. On the PR the
Swift check simply wasn't in the check-run list, which is exactly what a working exclusion
looks like; it was read as confirmation rather than checked. The run titled by file path,
one click away, said otherwise. **A check that is absent and a check that is skipped look
identical from the check list and mean opposite things** — `conclusion: skipped` in the
jobs API distinguishes them, and that is the thing to look at.

Note the neighbouring `timeout-minutes: ${{ matrix.language == 'swift' && 45 || 15 }}` was
fine and had worked for months: `matrix` *is* available there. Context availability is
per-key, not per-file, so "it works two lines up" proves nothing.

The fix drops the matrix entirely for two explicit jobs — `analyze-actions` and
`analyze-swift`. Each condition then sits in a context that can see it, and the workflow
reads as what it is: two unrelated analyses that never shared anything but a `steps:` block.

**The schedule.** With that corrected, the Swift analysis moved further than the original
change took it: from "every push and PR" to **scheduled runs only** (the existing Monday
cron, plus `workflow_dispatch`). One run per week is ~30 billed macOS minutes in total
rather than ~30 per push. A Swift finding now surfaces up to a week late instead of on the
PR — acceptable for an app with no server, no accounts, and no credential handling, where
the CodeQL Swift pack has never produced a finding. `analyze-actions` is unchanged and still
runs on every push and PR: it needs no build and runs free on ubuntu, so there is nothing to
save by moving it and real value in keeping workflow changes reviewed where they are made.

## 2026-08-11 (CI is rationed against one billed runner label)

Actions spend had become the largest cost of running this project, and measuring it before
changing anything located the whole of it in one place: the `xcode-27` label. ShoutKit is
public, so GitHub's standard hosted runners — `ubuntu-latest`, `macos-26` — are free.
`xcode-27` is a *larger runner*, and larger runners are billed on public repositories too.
Every mac job in the repo was on it.

Measured per push, from the API rather than from estimate (billing rounds each job up to
the minute):

| Job | Wall clock | Billed |
|---|---|---|
| CodeQL `Analyze (swift)` | 29m | 30 |
| CI `build` | 14m03s | 15 |
| CI `host-tests` | 3m28s | 4 |
| CI `lint` | 14s | 1 |
| | | **50 mac-minutes per push** |

The surprise was CodeQL, not CI. Its Swift analysis ran on every push *and* every pull
request, and CodeQL's build tracing turns the 4-minute Release build into a 27-minute one —
so the security scan cost more than the entire CI workflow beside it, on a UIKit radio app
where it has never produced a finding. It now runs on `main` and on the existing weekly
cron. That keeps the alert database current and gives up only per-PR alert annotations,
which is a fair trade at this merge rate. The `actions` analysis is untouched: it needs no
build, runs free on ubuntu, and stays on PRs.

The rest is three rules, applied in `ci.yml`:

- **Nothing expensive starts until `lint` passes.** Lint is ~15 seconds of work and it was
  running *beside* the mac jobs rather than in front of them. Run 31275068736 is the case
  that settled it: lint went red 7 seconds in, and `build` carried on for another 14 minutes
  on a tree that could not merge. `needs: lint` costs ~30s of added latency on green runs
  and stops that entirely.
- **Draft PRs get the cheap signal, not the expensive one.** `host-tests` (~4 min, eight
  packages) runs on drafts; the ~15-minute simulator job waits for `ready_for_review`. The
  branch names in the run history are almost all agent-authored, and those push many times
  per PR — which is where the minutes were actually going. `ready_for_review` had to be
  added to the trigger's `types` for this to work at all; without it, marking a draft ready
  fires no event and the skipped job never runs.
- **Compile-only checks move to `main`.** Release config and the watch app are ~5.5 of that
  job's 14 minutes and neither runs a test, so they split into `release-checks`, gated to
  push and `workflow_dispatch`.

That last one is a real regression in signal and is worth naming as such rather than
burying: a change that builds Debug-for-iOS but breaks Release or watchOS now goes red on
`main` instead of on the PR that caused it. Accepted because the failure mode is narrow
(Release-only breakage is nearly always `#if DEBUG` drift; watch breakage is nearly always a
shared-package API change), because it always surfaces as a compile error rather than as
something subtle, and because it is cheap to fix forward — whereas checking it on every push
was not cheap at all.

Net: a PR push goes from ~50 billed mac-minutes to ~5 (draft) or ~20 (ready), while `main`
keeps full coverage including CodeQL. Two smaller things landed with it — the CodeQL Swift
job had no SwiftPM cache at all and cold-resolved the workspace including the AudioStreaming
codec download every run, and `build`'s 75-minute timeout meant a wedged simulator could
bill 75 minutes for nothing (now 30, against an observed 8-9).

Explicitly *not* done: moving `lint` to a free ubuntu runner. SwiftLint has a Linux build,
but not full rule parity — the SourceKit-backed rules behave differently — and this job is
now the gate the other three trust. A gate that means something slightly different from what
contributors run locally is worse than a gate that costs one minute. Revisit if parity
closes.

None of this is the actual fix, which is to stop paying for the label: either the free
`macos-26` image gains a new enough Xcode, or the work moves to a self-hosted Mac mini.
`runner-image-watch.yml` is a weekly ubuntu job that watches for the former and files an
issue when it happens, because the alternative is nobody noticing for months while the meter
runs. `docs/ROADMAP.md` carries the sequencing for the latter, including the constraint that
matters most: a self-hosted runner on a public repo must not accept fork PRs.

## 2026-08-07 (`try?` audit: gate rechecked before deferring)

Issue #143 had been rolling forward behind "wait for Swift 6.4's unhandled-error
warning in `Task` closures", but every manifest was already at
`swift-tools-version: 6.4`, so repeating that gate was information-free.

- **Rechecked the gate explicitly.** A probe closure (`Task { try await … }`)
  typechecked on the current toolchains without an unhandled-error warning, so
  there is currently no warning to turn on in this tree.
- **Recorded a concrete arrival check instead of a vague wait.** The command
  `swiftc -typecheck -warnings-as-errors /tmp/task-unhandled-error-probe.swift`
  is the trigger: when that probe starts failing, the compiler has gained the
  diagnostic and the audit can switch from manual reasoning to compiler-driven
  enumeration.
- **Audited existing non-test `try?` call sites for intent.** The remaining
  sites are intentional best-effort paths (cache/file hygiene, advisory audio
  session tuning, non-blocking handoff/suggestions, cancellation-tolerant
  sleeps, optional artwork fetches) rather than user-facing hard failures.
- **Made ambiguous sites explicit in code.** The app/watch sync and shortcuts
  fallback paths, watch audio-session setup/teardown, defaults codable
  fallback, and media-session primary request now state their best-effort
  intent next to the `try?`, so an unexplained `try?` regains signal as a
  likely oversight.

## 2026-08-07 (Search filters over Radio-Browser)

- Added a dedicated `StationSearchFilters` model (bitrate min/max, tag, country
  code) and threaded it through `RadioDirectoryProviding` as explicit filtered
  overloads for both name search and genre browsing. Existing call sites stay
  source-compatible through default protocol implementations, while
  `RadioBrowserDirectoryClient` overrides to send native API params
  (`bitrateMin`/`bitrateMax`/`tagList`/`countrycode`) on the same endpoints the
  app already uses.
- Filter state is transient UI state on `SearchViewModel` (not persisted) and
  composes with both free-text queries and genre chips, matching the search
  surface contract established in the 2026-08-04 UX pass.
- Empty-search results now surface active filter context and include an explicit
  "Clear Filters" action to recover quickly from over-constrained queries.
- Missing metadata is treated as "unknown", not an automatic failure: local
  filter evaluation only excludes stations that positively fail the selected
  bounds (e.g. known bitrate below the minimum), to avoid collapsing discovery
  on sparse community data.

## 2026-08-07 (the codec dependency leaves Playback; CI starts measuring itself)

Three gaps that were gaps because nothing reported them, closed together because
they share a shape: the tree was correct and nobody could tell.

- **`AudioStreamingPlaybackEngine` moves to `Packages/PlaybackEngineAudioStreaming`,
  an iOS-only package only the app target links (#122).** The 2026-08-05 entry
  established that `condition: .when(platforms: [.iOS])` gates linking, not
  resolution — every `swift test` in `Packages/Playback` downloaded the ogg and
  vorbis xcframeworks to run a suite that links neither, and any adopter of the
  MIT-licensed `Playback` inherited the whole C codec stack. Expressing the
  boundary as *who links the package* fixes both and is harder to undo by
  accident than a target-dependency condition. Same shape as `DebugSupport`,
  which keeps Pulse out of the reusable packages.
- **The coupling was already narrow enough to make this a move, not a rewrite.**
  Two files imported AudioStreaming; everything else went through the
  `RadioPlaybackEngine` seam. The one genuine tangle was
  `PlaybackFailure.classify`, which is `internal` — so `PlaybackError` grew a
  public `classifying(_:)` rather than `PlaybackFailure` becoming public. The
  classification table belongs beside the cases it produces, and exporting a
  second error type to adopters buys nothing.
- **`Container.radioPlaybackEngine` now defaults to `StubRadioPlaybackEngine`
  everywhere**, with `registerProductionPlaybackEngine()` — a free function, the
  `registerProductionRadioDirectory` pattern — called from `bootstrap()` before
  the first `PlaybackController(directory:)`. The failure mode if that ordering
  is ever broken is silence rather than a crash, so the contract is stated at
  both ends: in the registration function and on the convenience `init`.
- **The new package stays MIT, like the code it came from.** It implements a
  public MIT protocol and is reusable infrastructure; `DebugSupport` is GPL
  because it is app-side glue, which this is not. Relicensing already-published
  MIT code would also be a decision worth more than a file move.
- **A CI step now asserts `Packages/Playback` resolves no binary artifacts.**
  Re-declaring AudioStreaming in that graph would silently restore the download
  and nothing else would notice — the original problem was invisible for months
  for exactly that reason. Checks the workspace artifact tree, not the shared
  store, which is cache-restored and can hold artifacts another job fetched.
- **Coverage is collected and published, with no gate.** `ShoutKit.xctestplan`
  had empty `defaultOptions` and the host `swift test` runs passed no flag, so
  nothing anywhere measured coverage. Both now do, reported per package and per
  iOS target into the run summary. Deliberately no threshold: a gate on a tree
  that has never measured buys tests for whatever is cheapest to cover.
- **The watch app is compiled by CI for the first time.** `ShoutKitWatchApp` is
  a separate top-level target — not in `ShoutKit`'s dependencies, not in its
  Embed Foundation Extensions phase — and had no shared scheme, so ~670 lines
  could break with every check green. The widget extension *was* already
  covered; `ShoutKit` does depend on and embed `ShoutKitWidgets`.
- **Confirmed against a real build: the watch app does not ship with the phone
  app.** The suspicion came from `project.pbxproj` — no `Embed Watch Content`
  phase anywhere, and `ShoutKitWatchApp` absent from `ShoutKit`'s dependencies —
  and rather than act on a reading of the project file, CI was made to print
  what the built bundle contains. It reports no `Watch/` payload in
  `ShoutKit.app`. So the watchOS companion recorded on 2026-07-16 and advertised
  in `README.md` has never installed alongside the app, on any build anyone has
  made. Tracked as a P1 in `docs/ROADMAP.md`; the fix needs Xcode, because
  hand-editing an embed phase into a shipping app target is how you get a bundle
  that builds green and fails validation. The check stays a warning until the
  embed exists, then becomes a hard failure.

  Worth noting how long this hid: the watch app compiled fine locally, its code
  was reviewed and merged, and every check was green — because nothing built it
  and nothing looked inside the product. A target that no job builds and no
  assertion inspects is indistinguishable from one that works.

- **The same CI step found a second defect: the watch app did not compile under
  Swift 6 strict concurrency at all.** `WatchRadioPlaybackEngine`'s
  `.AVPlayerItemFailedToPlayToEndTime` observer captured the whole `Notification`
  into a `Task { @MainActor }` and dereferenced it there. Neither `Notification`
  nor the `AVPlayerItem` it carries is `Sendable`, so that capture sends
  non-`Sendable` state across an isolation boundary — `sending 'notification'
  risks causing data races`, an error under the `complete` setting every target
  here uses.
- **Fixed with `queue: .main` + `MainActor.assumeIsolated`**, the same remedy
  `AudioStreamingPlaybackEngine+Session` already uses, and safe for the same
  reason: `OperationQueue.main` runs its blocks on the main thread, so the
  closure body and the isolated block are one synchronous region and nothing is
  sent anywhere. This callback specifically needs the failed `AVPlayerItem` to
  compare against the current one, so the extract-Sendable-values-first approach
  the two audio-session observers in that file use — which is why *they* always
  compiled — wasn't available.
- **The KVO observers in the same function were deliberately left alone.** They
  hop with `Task { @MainActor }` too, but CI flagged only the notification site,
  and KVO callbacks carry no queue guarantee, so `assumeIsolated` would be
  unsound there — `Task` is the right tool. Changing them on the suspicion that
  they look similar would be replacing a compiler's answer with a guess.
- **SwiftFormat gets a path to enforcement, not enforcement.** The one-time
  reformat needs a real toolchain; a `workflow_dispatch` job runs it on the same
  macOS image that judges the result and can push. `continue-on-error` comes off
  with the reformat, not before it, and the resulting SHA goes in the new
  `.git-blame-ignore-revs`.

## 2026-08-06 (Bluetooth/AVRCP artwork on the iOS 27 NowPlaying path)

Reported from a Tesla: text metadata and transport controls correct, artwork either frozen or
still showing the cover of whatever had played in Apple Music before ShoutKit launched. The lock
screen and CarPlay were fine, which localizes it — the car is an AVRCP client, and AVRCP is the
one now-playing consumer that pays a real cost per artwork change. It is told the track changed
and *then* fetches the image over a separate, slow (OBEX/BIP) channel; if the image isn't
available when it asks, or a second track-changed lands mid-transfer, it keeps the last image it
managed to fetch. On a fresh launch that image belongs to the previous audio app.

Three changes in July each made sense for the lock screen and together broke that contract. None
is a bug in isolation, which is why nothing caught it:

- Adopting the iOS 27 `NowPlaying` framework (`MediaSessionNowPlayingCenter`) replaced eager
  download-and-decode with a lazy async `Artwork` provider. `NowPlayingCenter`, the path it
  replaced, downloaded and decoded artwork up front and handed `MPMediaItemArtwork` a
  fully-materialized `UIImage`; the provider only *starts* a download when the system asks.
- #105 set the artwork request to `.reloadRevalidatingCacheData`, putting a conditional GET in
  front of every one of those lazy resolutions.
- Folding the artwork URL into the `RadioContent` id (the fix for the lock screen never showing
  album art) made every artwork change a content-identity change — and the controller pushes the
  station's own artwork the instant a new ICY title lands, then album art a lookup later. Two
  identity changes per song, i.e. two track-changed notifications and two cover-art fetches.

Raising the deployment floor to iOS 27 (#109) meant `NowPlayingCenter` — the path that carries the
Tesla-specific artwork handling, added when this was first diagnosed — stopped running on device
entirely. It stays in the tree as a working reference and a one-line fallback, not as dead weight.

- **Artwork is materialized before the identity that carries it is advertised.**
  `MediaSessionNowPlayingCenter` keeps a bounded (4-entry) dictionary of `ArtworkRepresentation`
  keyed by source URL. `update(...)` advertises a new artwork URL only once its bytes are resident;
  until then it keeps advertising what's on screen and fetches in the background, then replays the
  last push so the identity flips exactly once — with the image already in hand. The `Artwork`
  provider becomes a memory hand-off in the steady state. The lazy provider is still installed for
  a URL we don't hold (first play, or a fetch that failed), so the lock screen never regresses.
- **A fetch that fails marks its URL advertisable anyway.** Otherwise a URL we can't download would
  pin the previous track's cover on screen for the whole next song — the exact staleness this is
  meant to remove. The set is cleared on `clear()` and capped at 64 so a long drive on a bad link
  can't accumulate; dropping it just re-arms the retries.
- **`NowPlayingPresenting.update()` takes `NowPlayingArtwork`, not `URL?`.** `.resolving` is the new
  information: the controller knows, at the track boundary, whether a lookup is about to answer.
  Surfaces that can flip images for free ignore the distinction; the ones that can't hold what they
  have instead of bouncing through the station favicon. `PlaybackController` sends `.resolving` only
  when `trackResourcesProvider` is non-nil (album art off → nothing would ever release the hold),
  and `resolveTrackResources` now pushes its verdict **including a miss**, which is what bounds it.
  The decision itself lives in `NowPlayingArtworkPolicy` — pure and framework-free, so the host test
  suite covers it without the NowPlaying framework or MediaPlayer being available.
- **`.returnCacheDataElseLoad` on this path, reverting #105's revalidation for now-playing artwork
  only.** Artwork URLs are content-addressed (iTunes serves one `…600x600bb.jpg` per album; station
  favicons are stable), so a forced revalidation buys freshness nobody can perceive while adding a
  round-trip in front of a cover-art request. `NowPlayingCenter` keeps `.reloadRevalidatingCacheData`
  — it fetches once per station switch, not once per surface request — as do the DesignSystem
  loaders, where #105's reasoning is untouched.
- **Payloads over 512 KB are re-encoded rather than passed through.** A 3 MB station favicon is a
  slow Bluetooth transfer for no visible gain. Normalization (also the existing fallback for bytes
  `ArtworkRepresentation(data:)` rejects) is now 600 px rather than 1024 — it matches what the
  iTunes lookup asks for and covers the lock-screen tile. Still PNG, not JPEG: favicons routinely
  carry transparency that JPEG would flatten to black, and typical album art never reaches the
  threshold anyway.
- **Not done**: honoring a requested artwork size on this path, the way `NowPlayingCenter` does for
  strict AVRCP clients. The `NowPlaying` framework owns rendering for downstream consumers and its
  provider's request parameter is unused here; adding size negotiation on a guess about what the
  framework does with it would be speculation. Revisit if the fixes above prove insufficient
  on-device.

**Unverified on-device.** The diagnosis is from the code and the AVRCP contract, not from a car;
the fix wants a Tesla (or any Bluetooth head unit) with a station that carries ICY metadata,
watching that artwork changes once per track and lands within a few seconds of the title.

## 2026-08-05 (AppDependencies split into four extension files)

- **`AppDependencies.swift` was one line under the limit, which is a tax on the next
  feature, not a fact about this one.** At 399 lines against the 400-line `file_length`
  limit (and a `bootstrap()` body near the 50-line `function_body_length` limit), the
  equalizer port failed `swiftlint --strict` for reasons that had nothing to do with the
  equalizer, and the fix — moving preset restore into `PlaybackController` — bought back
  exactly one line. Split preemptively instead: the file is now 121 lines and every seam
  has room to grow.
- **The seams are the ones `bootstrap()` already delegates along**, one file each:
  `+Networking.swift` (the process-wide URL cache / shared session install that must run
  before anything requests), `+Factories.swift` (the diagnostics and directory stacks —
  both pick between concrete implementations and register with Factory, so they read
  better beside each other than apart), `+Callbacks.swift` (the controller's app-layer
  closures, plus the `PhoneWatchLastStationSync` that one of them feeds), and
  `+Warmups.swift` (the fire-and-forget Spotlight indexing and connection prewarm).
  What's left in `AppDependencies.swift` is the shared graph and the one call that
  assembles it. Same remedy and same `+Extension.swift` convention as the
  `PlaybackController+Internals`/`+Recovery` and `AudioStreamingPlaybackEngine+Session`
  splits, no lint-disable.
- **The helpers became `internal` because Swift's `private` is file-scoped**, so an
  extension in another file can't reach them. Each new file's header says so, and the
  members that stay within one file (`makeDiagnosticsPayloadStore`, `shoutcastAPIKey`,
  `watchLastStationSync`) kept `private`. `DirectoryServices` moved to `+Factories.swift`
  for the same reason — `bootstrap()` reads its members.
- **The app target isn't a SwiftPM package**, so each file needed a `PBXFileReference`,
  a `PBXBuildFile`, a group child, and a Sources entry in `project.pbxproj`, using the
  fixed zero-padded object IDs that project uses (`…000100`–`…000103` for the file
  references, `…000110`–`…000113` for the build files). Verified by confirming all four
  `.o` files land in the target's build directory — a file that fails to register still
  builds green, it just silently isn't in the binary.

## 2026-08-05 (equalizer, ported from the Android client's curve math)

- **`AudioStreamingPlaybackEngine`'s July engine swap quietly unlocked an equalizer.** The prior
  `AVPlayer`-backed engine had no supported way to insert a filter into its render chain, so the only
  "equalizer" anywhere in the tree was `PlayingIndicator` (an animation). AudioStreaming's `AudioPlayer`
  is `AVAudioEngine`-backed and exposes `attach(node:)`/`detach(node:)` for exactly this; the sibling
  Android client (sir-android) already ships an equalizer built the same way, so this ports its band
  math rather than inventing new curve behavior.
- **Ported `EqualizerPreset`/`EqualizerCurves` verbatim** from `core/playback` in sir-android: each
  preset owns its own gain curve — a pure function from normalized band position to a normalized gain
  fraction — instead of a `switch` living in the engine, and `EqualizerCurves` maps a curve onto a
  given band count and gain range with **no dependency on any platform audio type**, so it's covered by
  plain Swift Testing unit tests exercised the same way the Kotlin side is by JUnit. One decision copied
  verbatim from the Android side: `.normal` has **no curve** (0 dB on every band), not the midpoint of
  the range — on an asymmetric range the midpoint is not flat, and "Normal" would quietly colour sound.
- **The attach point lives in `AudioStreamingPlaybackEngine+Equalizer.swift`**, a new file (mirroring the
  existing `+Session` split for the 400-line `file_length` limit). It creates an `AVAudioUnitEQ`,
  attaches it via `AudioPlayer.attach(node:)`, and applies `EqualizerCurves`-computed gains — with a
  conservative `-12...12` dB range rather than the unit's full `-96...24`, since this is a listening-color
  preset, not a mastering tool, layered on a live stream already at unity gain. Because
  `handleMediaServicesReset()` rebuilds the whole `AudioPlayer` (and therefore its `AVAudioEngine`) from
  scratch, the equalizer node is re-attached there too, or it would silently vanish on the next reset.
- **`RadioPlaybackEngine` grew `supportsEqualizer`/`setEqualizerPreset(_:)` with a default "no EQ"
  extension** rather than a required, always-implemented pair. `StubRadioPlaybackEngine` and the watch's
  `WatchRadioPlaybackEngine` (still `AVPlayer`-backed; watchOS has no reason to move off it) get "no EQ"
  for free instead of stub implementations, and `PlaybackController.supportsEqualizer` lets the settings
  UI hide the control entirely on those engines rather than show one that does nothing.
- **Preset choice persists through `SettingsStore`** as a raw `Int` (`EqualizerPreset.rawValue`) rather
  than the `Playback` package's enum type, keeping `Persistence` free of a `Playback` dependency the way
  every other stored setting there already is.

## 2026-08-05 (CI caches the SwiftPM store; the ogg/vorbis artifacts aren't pinned by Package.resolved)

- **Both resolving jobs (`host-tests`, `build`) now cache the SwiftPM store.** Neither had any cache,
  so every run re-fetched the whole dependency graph — including AudioStreaming's two transitive
  `binaryTarget` packages, the ogg and vorbis xcframeworks, at ~5.6 MB zipped and ~22 MB unpacked
  *per resolving job*.
- **The reason this is more than a speed fix**: the artifacts are fetched live from third-party
  GitHub *release assets* (`github.com/sbooth/{ogg,vorbis}-binary-xcframework/releases/download/...`)
  on every cold resolve. Integrity is covered, by the chain the 2026-07-13 entry already described:
  `Package.resolved` pins each package by revision, that revision's manifest carries the
  `binaryTarget` SHA-256, and the downloaded zip must match it. Note the checksum lives in the
  *pinned manifest*, not in `Package.resolved` — a v3 lockfile records only `revision` and
  `version`, and `grep -c checksum` over every `Package.resolved` in this repo returns zero. What
  the chain does *not* underwrite is *availability*: delete or re-cut either release and CI breaks
  with no local copy to fall back on. This sharpens the provenance concession recorded under
  2026-07-13 (AudioStreaming): we already accepted trusting sbooth's builds; we had also, without
  saying so, accepted depending on them staying downloadable. A warm cache is the cheap half of the
  answer; self-hosted static xcframeworks would be the real one.
- **Correction to the 2026-07-13 AudioStreaming entry**, in the same spirit as the `#if DEBUG`/Pulse
  correction above it. That entry claims the `condition: .when(platforms: [.iOS])` gate means the mac
  host job "never fetches or links" AudioStreaming. *Links* is right; *fetches* is not. A platform
  condition applies to a **target** dependency — `.package(url:)` takes no condition (SwiftPM has no
  such API), so the repo is cloned and its manifest read unconditionally. Binary artifacts are then
  enumerated with no platform or condition filtering whatsoever; from SwiftPM's
  `Workspace+BinaryArtifacts.swift`, `parseArtifacts` walks
  `for target in manifest.targets where target.type == .binary` over root *and* dependency manifests.
  So `swift test` in `Packages/Playback` downloads both xcframeworks before running a suite that
  links neither. Same class of mistake as the Pulse one: assuming a source- or platform-level gate
  implies dependency-graph absence.
- **Confirmed by observation, not left as inference.** The cold-cache `host-tests` run on PR #127
  (run 422, job log 04:09:07Z) logged `Downloading binary artifact
  https://github.com/sbooth/vorbis-binary-xcframework/releases/download/0.1.2/vorbis.xcframework.zip`
  and the ogg equivalent — inside the **second** `swift test` step, which is `Packages/Playback`,
  the suite that links neither. The very next run, with the cache warm, logged `Fetching binary
  artifact … from cache (0.33s)` and `Cache hit occurred on the primary key, not saving cache`
  instead. That pair settles both questions at once: the platform gate does not spare this job the
  fetch, and the cache does eliminate it.
- **Cache keys fold in a toolchain fingerprint** (`swift --version` / `xcodebuild -version`, hashed)
  alongside the resolved-file hash. `xcode-27` is a rotating beta image and SwiftPM's
  manifest-compile cache is toolchain specific; keying the whole store on the toolchain is cheaper
  than reasoning about which parts of it survive an image bump. `restore-keys` falls back on the
  toolchain prefix so a `Package.resolved` change reuses the unchanged majority instead of
  re-fetching everything.
- **The `build` job caches `DerivedData/SourcePackages`, not `DerivedData`.** Xcode splits the work:
  downloaded artifacts land in the shared `~/Library/Caches/org.swift.swiftpm` store, while the
  per-workspace checkouts and resolved artifact tree live under the derived-data path. Both are
  restored. Build *products* are deliberately excluded — the Pulse symbol checks in this job have to
  reflect this commit's actual link result, and a cached `Products/` directory would quietly hollow
  them out.

## 2026-08-04 (UX pass: one discovery surface, and controls that mean one thing each)

A simplification pass over the shell and the three screens people actually spend time in, taking
Apple's Human Interface Guidelines as the arbiter rather than "it works". The recurring finding was
duplication that had become invisible from the inside: the same content reachable two ways, the
same accessibility branch written twice, the same failure rendered three ways.

- **The Browse tab is gone; Listen Now is the only discovery surface.** Browse and Listen Now issued
  the *same* `topStations` fetch and drew it twice — and Browse drew it twice again on its own
  screen, as a carousel of the first ten stations directly above a grid that began with those same
  ten. Its genre strip duplicated Search's. HIG's "one place for one thing" reading of tab bars is
  hard to satisfy when two tabs answer the same question, so Listen Now absorbed the station list as
  a **More Stations** section fed by `stations.dropFirst(carouselLimit)` — disjoint from the
  carousel above it, so nothing appears twice — and genre browsing consolidated into Search. Three
  tabs: Listen Now · Search · Favorites. Nothing was dropped, only de-duplicated: every station,
  genre, and control that was reachable before still is.
- **A genre chip now browses the genre instead of searching its name.** Search's chips set
  `query = genre.name`, which ran `searchStations` — so tapping "Jazz" returned stations *called*
  Jazz. `RadioDirectoryProviding.stations(inGenre:limit:)` (the tag query Browse was already using)
  is now what a chip calls, tracked by `SearchViewModel.activeGenre`. The name still lands in the
  field so the result set is labeled and the field's Clear button gets you out, and typing over it
  drops back to a name search. Chips render selected while their genre is showing, and `retry()`
  re-issues the same *kind* of request rather than silently downgrading a failed genre browse.
- **Recently Played on Listen Now is no longer a `List` inside a `ScrollView`.** The nested list
  existed only to get `swipeActions`, and a nested list has no intrinsic height, so it was given
  one: `count * 76 + spacing`. 76 pt is a guess about a row whose height is set by Dynamic Type, so
  at the first size step up the section clipped its last row. Dismissal moved to the row's context
  menu (with a matching VoiceOver custom action, since a context menu is invisible to it) — where
  iOS puts "remove this suggestion" anyway. The undo banner moved from `overlay(alignment: .bottom)`
  to `safeAreaInset(edge: .bottom)`: as an overlay it rendered underneath the tab bar's mini-player
  accessory, which is exactly where the bottom of that screen is.
- **Now Playing's transport row is Favorite · Play/Pause · Sleep timer.** Stop sat beside play/pause
  — one 8 pt gap between the control people tap constantly and one that ends the stream *and*
  dismisses the screen, in a player where pause already does the audible half of stopping. It moved,
  with "View in Apple Music", into an overflow menu on the trailing edge of the title block, which
  is also where the title moved: leading-aligned, because centered text with no anchor drifts as
  soon as a long station name and a long track title disagree about line count. AirPlay is alone on
  the bottom row and genuinely centered now, instead of centered by a `Color.clear` spacer
  counterweighting the sleep timer. The artwork's long-press menu went away with the ellipsis menu
  arriving — one discoverable path beats one discoverable and one hidden.
- **`shoutKitBackground` is the system grouped background, not a hand-mixed near-white/near-black.**
  A fixed pair of RGB values can't track what the system shifts underneath it — sheets, popovers,
  and elevated presentations, Increase Contrast, and the inset-grouped `List` style Favorites uses.
  Paired with a new `shoutKitCardBackground` (`secondarySystemGroupedBackground`) for `StationRow`,
  which was filling with `.background`: on the old canvas that read as a card, and on any surface
  the system paints `systemBackground` it was white on white.
- **The accent has two appearances.** One fixed blue (0.04, 0.44, 0.72) has to be dark enough to
  read as text on white, which makes it too dark to read as tinted text or a glyph on near-black —
  and it was doing both. Dark mode gets a lifted variant at comparable contrast; same for the
  favorited heart's `shoutKitHighlight`.
- **`glassControlBackground(in:)` is the one glass-or-material decision.** `GlassControlSurface`
  owned that branch and had **zero call sites**, while `StationRow` carried a hand-copied version
  under a comment promising it matched — the kind of promise that quietly stops being true. Both now
  call one view modifier, and the Listen Now undo banner uses `GlassControlSurface` itself, so the
  banner degrades under Reduce Transparency like every other glass control (as a bare
  `.regularMaterial` background it didn't).
- **`DirectoryUnavailableView` replaces three hand-rolled copies.** Listen Now, Search, and the
  genre strip each had their own `ContentUnavailableView` with the same icon, the same retry
  gating, and different minimum heights — so one failure looked like three different failures
  depending on where you were standing.
- **Deleted: `SpotlightCard` and `BrowseConfiguration`.** The featured-station hero had been behind
  a compile-time `false` since beta 1 for a reason its own comment stated — it's the first directory
  result, not editorial content, so it wasn't earning a 220 pt hero. Dead UI kept alive by a flag
  nobody was going to flip; `BrowseContent.spotlight` stays on the view model (it's tested, and
  costs nothing) so bringing an *earned* hero back doesn't start from zero. `GlassActionCluster`
  went the same way — a public wrapper around `GlassEffectContainer` with no callers.
- **Deliberately not done: renaming the `BrowseFeature` package.** The module now holds Listen Now
  and nothing named Browse, which reads oddly, but the rename touches five manifests and every
  import for zero behavior change. Left as a name that's a little wrong rather than churn that's
  entirely cosmetic.
- **Deliberately not done: removing the first-run welcome screen.** HIG is unenthusiastic about
  anything between launch and content, and this is a single screen with a single button. It states
  the one thing worth stating (no account, tap to listen) and never returns. Not the friction worth
  spending a behavior change on.

## 2026-08-03 (power review: what the app spends when nobody asked it to)

A pass over hardware efficiency and the power signals the platform offers. The finding was
uniform: the app reads **none** of them. `isLowPowerModeEnabled`, `thermalState`,
`NSProcessInfoPowerStateDidChange`, `NWPath.isExpensive`/`isConstrained`,
`allowsConstrainedNetworkAccess` — zero occurrences across the tree. Accessibility signals are
handled well (`accessibilityReduceMotion` / `reduceTransparency` are respected in
`HeroArtworkView`, `PlayingIndicator`, `AmbientArtworkBackdrop`, `StationRow`), so the gap is
specifically power, not system-signal awareness in general.

- **Speculative traffic now travels on its own session.** Everything shared one
  `URLSessionHTTPTransport.shared`, configured `.responsiveData` with expensive and constrained
  network access at their permissive defaults. That is right for a stream endpoint the listener is
  waiting on and wrong for artwork six rows below the fold: on Low Data Mode or cellular the app
  was spending the user's allowance on work they never asked for, at foreground priority.
  `speculativeConfiguration()` refuses constrained and expensive paths and asks for `.background`
  scheduling; `ArtworkThumbnailLoader.prefetch` uses it. Deliberately *not* applied to the row's
  own load, the directory, or playback — a visible row still fetches over the interactive session.
  The two compose because failures are never cached: a prefetch the network refuses simply leaves
  the artwork to load normally when the row appears.
- **Low Power Mode disables the two purely speculative paths outright** — station connection
  prewarming and artwork prefetch. Both trade radio time now against latency the listener may never
  benefit from, which is a good trade normally and the wrong one at 20% battery. Skipped in full
  rather than trimmed: warming three hosts instead of five still spends the radio for the same
  speculative reason.
- **Sampled per call, not observed.** Both sites are re-entered constantly (prewarm at launch,
  prefetch on every row appearance), so reading `ProcessInfo` at the decision point tracks a mode
  the user can toggle mid-session without any of the bookkeeping a
  `NSProcessInfoPowerStateDidChange` observer would need. An observer buys nothing here and is the
  kind of state that goes stale.
- **Deliberately not done: `UIDevice.batteryLevel` / `batteryState`.** Reaching for the raw level
  to make our own conservation policy would duplicate — and disagree with — the system's, which
  already accounts for charging state, thermals, and user intent. Low Power Mode *is* that signal;
  polling battery percentage is the anti-pattern it exists to replace.
- **Deliberately not done: thermal throttling.** `thermalState` is the right lever for sustained
  GPU or compute load, and this app has neither: `AmbientArtworkBackdrop` renders once per artwork
  change (no `repeatForever`), `PlayingIndicator` runs at ~8 fps and pauses on
  `scenePhase != .active` or Reduce Motion, and the only 1 Hz `TimelineView` is gated on
  `sleepTimer.isActive`. Decode is already bounded by ImageIO downsampling. Adding a thermal
  observer would be ceremony without a workload to throttle.
- **Background refresh needs nothing.** `BGTaskScheduler` already defers discretionary work in Low
  Power Mode at the system level; duplicating that check would be redundant.
- **Left open:** `AVAudioSession.setPreferredIOBufferDuration` is unset, so playback runs at the
  default IO buffer. A longer buffer means proportionally fewer render wakeups across a long
  background listen, which is the single largest remaining battery lever for a radio app — but it
  trades against resume latency and interacts with AudioStreaming's own buffering, so it wants
  device measurement rather than a guessed constant.

## 2026-08-03 (external iOS review: ATS, root gestures, a stranded spinner, untested bundles)

Four findings from an outside review of the whole tree. Each was invisible from inside the
codebase for the same reason — the code reads correctly and the mistake is one level down, in a
plist key, a gesture modifier's semantics, a statement's position, or a CI action that was never
invoked.

- **The ATS exception was a typo, so ATS was fully enforced.** Both Info.plists carried
  `NSAllowsArbitraryLoadsInMedia`, which is not an App Transport Security key — the real one is
  `NSAllowsArbitraryLoadsForMedia`. iOS ignored it silently, so every cleartext station was
  blocked, and no build or lint step could have caught it. Fixing the spelling wasn't enough for
  iOS, either: `...ForMedia` only covers AVFoundation's own media loading, and iOS playback runs
  through AudioStreaming, which fetches the stream with `URLSession`. So the iOS app now sets
  `NSAllowsArbitraryLoads` (and *only* that key — iOS ignores it outright when any of the narrower
  `...ForMedia` / `...InWebContent` / `...InLocalNetworking` keys are also present, which would
  have reintroduced the bug in a subtler form). The watch app keeps the narrow
  `...ForMedia` key, correctly spelled: `WatchRadioPlaybackEngine` plays through `AVPlayer` and the
  watch issues no other requests. Everything the app itself talks to remains https; the relaxation
  is for third-party stream endpoints, which are frequently http-only with no TLS endpoint at all.
  Considered and rejected: upgrading stream URLs to https the way
  `RadioBrowserDirectoryClient.artworkURL(from:)` upgrades favicons. That's fine for artwork, where
  the failure mode is a placeholder, but a station that doesn't serve TLS would simply stop playing.
- **`simultaneousGesture` on the root meant every horizontal drag also switched tabs.** The
  swipe-between-tabs gesture on `RootView` fired *in addition to* whatever the child gesture did,
  so dragging a `StationCarousel`, swiping a row to delete in Favorites or the Listen Now teaser,
  or using a `NavigationStack`'s interactive back-swipe all changed tabs once the drag passed 70pt.
  Removed rather than constrained: the only filter that would separate a tab swipe from those is
  "starts near a screen edge", which is the back-swipe's own trigger. Apple Music and the system
  `TabView` don't page between tabs either, so the removal matches the pattern the rest of the app
  already follows.
- **One statement above a guard could strand Search on its spinner forever.**
  `SearchViewModel.query`'s `didSet` cancelled the in-flight search *before* checking whether the
  trimmed query had actually changed. Any edit that trims to the same string — a trailing space, an
  autocorrection, a paste with surrounding whitespace — therefore killed the running search, and
  the duplicate guard then returned without re-issuing it. `performSearch` bailed on its
  cancellation check without publishing, so `phase` stayed `.searching` with nothing left to
  complete it. The cancel moved below the guard. The existing whitespace test passed throughout
  because it waited for the search to *finish* before adding the space; the new one holds the fake
  directory open so the edit lands while the search is genuinely in flight.
- **Four test bundles were maintained but never executed.** CI ran `swift test` for seven packages
  and `xcodebuild build` twice — and no `test` action anywhere. `ShoutKitTests`, `DesignSystemTests`,
  and `NowPlayingActivityCoreTests` can't build for the mac host (app target; UIKit; iOS-only
  manifests), so none of them ran in any job, and `ShoutKit.xctestplan` was inert. The Debug half of
  the `build` job now runs `xcodebuild test` against a concrete simulator instead of a bare build,
  and the test plan gained the two package suites. Folded into the existing job rather than added as
  a new one so the Debug app is still built exactly once; the Pulse symbol check reads the same
  build product either way.
- **The first run of that job immediately found a crash, and three tests are quarantined for it.**
  Decoding a `StationEntity` traps in `EntityProperty` (see #116): the type is both
  `@AppEntity(schema:)` and `Codable`, and the schema macro's synthesized property storage doesn't
  survive the synthesized `Codable` round-trip. Two `IntentSupportTests` cases and one
  `AppIntentsPathwayTests` case are `.disabled(…)` against it so the other suites can start gating
  merges now, rather than holding CI enforcement hostage to a production fix in Siri/Shortcuts code.
  A disabled test is visible in every run and the reasons name the root cause, so this is a marker
  rather than a sweep — but the marker only pays off if #116 actually gets picked up. Worth noting
  what the quarantine does *not* cover: `IntentStationCache.load()` is on the launch path, so if the
  diagnosis holds, a populated cache crashes the app at launch in shipped builds. That is a device
  check, not a CI one.

## 2026-07-31 (OS disruptions: what happens to a stream when the system takes over)

An audit of the interruption path — everything that happens when iOS takes the
audio session away and gives it back (call, alarm, Siri, another app, a
notification, a route change, an audio-server restart). Six defects and one
missing piece of session configuration, all in the same seam: the app was faithful
about *losing* audio and unreliable about getting it back.

- **A notification should duck live radio, not pause it.** The session is now
  configured with `setPrefersNoInterruptionsFromSystemAlerts(true)`, so ordinary
  system alerts lower this stream for their sound instead of interrupting it. That
  removes the whole class at the source: an alert that never becomes an
  interruption cannot leave playback paused. Genuine interruptions (calls, alarms,
  Siri) are unaffected — they still arrive, and are still handled below.
- **A hintless `.ended` now resumes, under three guards.** The old rule was "resume
  only if `AVAudioSessionInterruptionOptions.shouldResume` is set", which is
  Apple's letter but leaves the listener's station silent whenever iOS omits the
  hint — in a pocket or a car, the loudest failure this app has. Ignoring the hint
  entirely is worse (it steals the session back from whatever the listener
  started), so the resume is gated on all three of: the stream was running when the
  interruption began, no other app holds audio now (`isOtherAudioPlaying`, carried
  to the controller on the status enum rather than queried behind its back), and
  the interruption ended within `hintlessResumeWindow` (90 s). The window is the
  line between "the OS borrowed the session" and "the listener moved on"; a long
  interruption with no hint stays paused, which is the old behavior. Tuning it is a
  one-line change, and `PlaybackInterruptionTests` pins every branch.
- **Arming is per-interruption.** `resumeAfterInterruption` was only ever cleared
  on the paths that consumed it, so an interruption iOS never ended — it does not
  guarantee an `.ended` for every `.began` — left the flag set indefinitely. The
  *next* interruption to end with a resume hint then started audio from a station
  the listener had left paused. `handleInterruptionBegan` now disarms before
  re-arming, and only the `.playing`/`.buffering`/`.loading` branches arm at all.
- **A refused session activation is no longer silent.** `activateSession()` was
  `try? setActive(true)`, and the failure was routine: the system commonly refuses
  activation for a moment either side of a disruption. The engine then started (or
  "resumed") the player into a session it did not have — no audio, no callback, and
  the app reporting playing. Activation now returns whether it succeeded, retries
  on a short backoff (~3.5 s across four tries), and starts the player only once
  it is real; if it never becomes real the engine reports a *retryable* failure so
  the controller's existing bounded reconnect owns the next attempt instead of a
  new parallel retry mechanism.
- **A media-services reset is recoverable.** `mediaServicesWereResetNotification`
  was unobserved. When the audio server restarts, every audio object in the
  process is dead — including the `AVAudioEngine` inside AudioStreaming's player —
  and the session configuration is gone, so no retry of the *existing* player ever
  worked: playback stayed silent until the app was relaunched. The engine now
  rebuilds the player and reconfigures the session, then reports a retryable
  failure to rejoin through the reconnect path. Delegate callbacks are matched
  against the current player by `ObjectIdentifier` (`Sendable`, unlike the player)
  so a discarded engine finishing its teardown can't drive playback state.
- **A route disconnect only pauses what was playing.** The `.oldDeviceUnavailable`
  handler called `pause()` unconditionally, which reported `.paused` from an idle
  or failed state — silently rewriting a `.failed` into a pause with a play button,
  and cancelling a pending reconnect. It now checks the player is actually
  playing or buffering first.
- **Volume is deliberately still untouched.** The audit looked for it: the app
  reads no volume, renders no volume control, and shouldn't — system volume is the
  listener's, and ducking during an alert is the system's. What *was* missing on
  iOS was the `.longFormAudio` route-sharing policy (the watch engine already asked
  for it), which is what makes this app the system's long-form audio app for
  AirPlay 2 routing and shared-route volume handling. Set now, with a fallback to
  the plain category so a throwing `setCategory` can never be the reason a stream
  plays silently.
- **`PlaybackController+Interruptions.swift` and
  `AudioStreamingPlaybackEngine+Session.swift`.** Both changes pushed their files
  past the 400-line `file_length` limit (`swiftlint --strict`), so the interruption
  policy and the engine's session ownership each moved to a sibling file — the same
  remedy as the earlier `+Internals`/`+Recovery` splits, no lint-disable. The
  interruption policy in particular earns a named home: the two halves are
  asymmetric (a beginning is a fact to mirror, an ending is a decision), and that
  decision is the thing a future reader will want to find.
- **Not adopted: resuming when the app returns to foreground.** An interruption the
  system never ends leaves the station paused with a working play button, and
  auto-playing on foreground would mean audio the listener didn't ask for at the
  moment they picked up the phone for something else. The lock-screen and
  mini-player play buttons already recover in one tap.
- **Not adopted: suppressing `.notifyOthersOnDeactivation` during a reconnect
  gap.** Tearing down for a rejoin deactivates the session, which invites other
  apps to resume in the backoff window; the reconnect then takes it back. Fixing it
  means teaching `AudioOutput.stop()` the difference between "the listener stopped"
  and "we are about to rejoin", and the churn is inaudible today. Noted rather
  than done.

## 2026-07-30 (stations on disk: launch without waiting for the directory)

Reported from real use: opening the app before a drive, or on a weak connection,
meant watching "Tuning in…" before any station could be tapped — and when the
list did arrive it had reshuffled, because Radio-Browser's top-click ranking
drifts continuously. `CachingRadioDirectory` already coalesced Listen Now's and
Browse's launch fetches, but its cache was in-memory with a 60-second TTL, so it
contributed nothing to a cold launch: every process start began with a network
round trip, and no connection meant an error page instead of a station list.
`BackgroundRefreshController` was warming that same in-memory cache every four
hours, which died with the process that warmed it.

- **The snapshot is a separate tier, not a longer TTL on the existing one.**
  Successful `topStations`/`genres` fetches are now written to a
  `DirectorySnapshotStoring` (a JSON file), but `topStations(limit:)` and
  `genres()` deliberately still mean "what the directory says now" — they never
  serve the file. The saved copy is reachable only through the new
  `DirectoryDiscoveryCaching` seam. That separation is what lets a surface know
  whether it is showing live or saved content; folding the file into the existing
  calls would have made every result ambiguous, and the "showing saved stations"
  note unimplementable without guessing.
- **The stability window (6 h) is a decision not to fetch, not a decision to
  hide staleness.** Inside it, `BrowseViewModel.refresh()` renders the snapshot
  and stops — no request at all — so repeat launches in a day show a byte-identical
  list. That directly answers the "it does not change frequently" half of the
  request, and cuts directory traffic (Radio-Browser etiquette) rather than just
  hiding latency. Outside the window the snapshot still paints first and live
  content swaps in behind it, so the wait is gone either way. Pull-to-refresh and
  the 4-hourly background wake both bypass the window; `invalidateMemoryCache()`
  exists because otherwise the 60-second in-memory window would answer a
  pull-to-refresh without going anywhere near the network.
- **A failed fetch no longer replaces a usable list with an error page.** Saved
  stations outlive it, with a one-line note explaining they aren't live. The
  error page is now reserved for a screen with nothing on it — which, after the
  first successful launch, means never. The same guard covers an
  answered-but-empty directory response: it can report "No Stations" only when
  there is nothing to fall back to.
- **Snapshots are scoped by source identity** (`radio-browser;country=US;language=en`,
  or `shoutcast`), evaluated per read and write rather than captured at
  construction, because `MutableRadioBrowserGeoFilterProvider`'s filter changes at
  runtime. Without it, travelling — or toggling the geo-stations flag — would serve
  another region's stations for up to the stability window. A mismatch reads as
  "no snapshot", so the content is simply refetched.
- **Application Support, not Caches**, even though the content is regenerable and
  Caches is the conventional home for it. The whole point of the file is to be
  there on the launch where the network isn't, and the system may evict a Caches
  directory at any time. It's excluded from backup instead (per-file, not on the
  shared `ShoutKit/` directory — the diagnostics database lives there too and its
  backup policy isn't this type's to decide). The file is a few KB.
- **Versioned in the file name** (`DiscoverySnapshot.v1.json`) rather than with a
  schema field: a future shape change simply finds no file and refetches, and
  decode failures already degrade to "no snapshot" on the same path as a first
  launch.
- **Not persisted: search results and per-genre station lists.** Both are
  user-driven, keyed by arbitrary strings, and neither is on the path being fixed
  (the wait at launch). Tapping a genre chip still needs the network, and still
  says so. Favorites and recents were already offline — they're SwiftData-backed —
  so the mini-player and Favorites tab were never part of this problem.

## 2026-07-24 (resume must never be a silent no-op)

Reported from real use: after pausing, tapping play did nothing at all — no
audio, no error, no state change — and the only way back was switching stations
and returning. `AudioPlayer.resume()` (AudioStreaming 1.4.4) returns immediately
unless the library's *own* internal state is exactly `.paused`, and it reports
nothing when it declines. `AudioStreamingPlaybackEngine` was reporting `.paused`
to the controller unconditionally, so any drift between the two states produced a
`.paused` the controller could never leave: `output.resume()` kept poking a
player that had already moved on. Two drift sources found — the system stops the
audio engine for an interruption (call, Siri, alarm) without informing
AudioStreaming, and the library's end-of-stream path (which a live stream reaches
whenever the server closes the connection) leaves it `.stopped`, a transition the
engine's `audioPlayerStateChanged` switch was discarding. `play(url:)` recreates
the audio entry from scratch, which is why picking another station cleared it.

- **Fixed at the source, then guarded at the layer above.** The engine now
  rejoins the stream itself when the player isn't resumable (`player.state !=
  .paused`), and surfaces an unrequested `.stopped` as a retryable
  `.streamFailed` so a dropped live stream reaches the existing bounded
  reconnect instead of showing a dead stream as playing. On top of that,
  `PlaybackController` arms a **resume watchdog**: if `state` hasn't left
  `.paused` within `resumeWatchdogTimeout` (default 2 s, injected like the other
  hygiene windows), it tears the player down and rejoins. Belt *and* braces
  deliberately — the same silent-refusal shape exists in
  `WatchRadioPlaybackEngine` (`AVPlayer.play()` does nothing for an ended or
  failed item), and the watchdog covers any future `AudioOutput` without each
  backend having to re-learn the lesson. Recovery is orchestration, so it belongs
  to the controller, consistent with the 2026-07-10 reconnect entry.
- **The controller now keeps the output's state in step rather than only its
  own.** `handleInterruptionBegan` calls `output.pause()` (and, in the `.loading`
  window where the stream has started but no status has landed, `output.stop()`
  instead of silently dropping the flag). A state machine that narrates a pause
  its player never heard about is the bug class, not an implementation detail.
- **Engine-side failure reports are deduped per stream.** One collapse can
  surface as both an `AudioPlayerError` and a `.stopped` transition, and each
  report the controller sees spends another reconnect attempt. A stop the player
  took *because of* an error still defers to `audioPlayerUnexpectedError`, which
  carries the classified reason.
- **`PlaybackController+Recovery.swift`.** The watchdog pushed
  `PlaybackController+Internals.swift` past the 400-line `file_length` limit
  (`swiftlint --strict`), so the timer-driven housekeeping and recovery (paused
  release, resume watchdog, stall ceiling, bounded reconnect) split into a
  sibling file — same remedy as the 2026-07-10 `+Internals` split, no
  lint-disable. New coverage lives in `PlaybackResumeRecoveryTests` for the same
  reason: folding it into the existing suites walked their bodies up toward the
  `type_body_length` limit.
- **Not adopted: making every resume a restart.** Live radio has no position to
  preserve, so unconditionally re-playing on resume would also be *correct* — but
  it spends a re-buffer on every pause/play, including the common case where the
  player is perfectly resumable. The watchdog pays that cost only when the fast
  path actually fails.

## 2026-07-18 (0.3.0 QA-checklist outcomes: streaming intents, artwork caching)

- **Streaming intent responses ("still working…") — not adopting.**
  `PlaybackController.play(_:)` is fire-and-forget: it kicks off endpoint
  resolution + buffering and returns synchronously, so `PlayStationIntent.perform()`
  returns "Playing …" immediately and never blocks on a resolve-then-buffer
  window. `WarmupRadioAudioQueueIntent` already prewarms the socket. A streaming
  response would only add value if `perform()` awaited first-audio — which is
  worse for headless Siri playback (Siri would wait on the buffer). Revisit only
  if the play intent ever becomes await-until-playing.
- **`AsyncImage` HTTP-caching free win — confirmed, no change.** Radio-Browser
  favicons ship `cache-control: max-age=31536000` + `etag`, so the shared
  `URLCache` caches them. Station artwork already routes through `URLCache`
  (`.returnCacheDataElseLoad`) in `ArtworkThumbnailLoader`/`ArtworkLoader` — the
  app uses those, not `AsyncImage`, for list rows. The `NSCache` tier holds
  *decoded* thumbnails (not raw bytes), so it's complementary to `URLCache`, not
  redundant caching to drop.

## 2026-07-18 (App Intents Testing + first app-hosted test target)

Adopted the iOS 27 **App Intents Testing** framework for the Siri intents, which
required standing up the project's **first app-hosted unit-test target**
(`ShoutKitTests`) — the intents live in the app target and App Intents testing
resolves the app's extracted metadata, so it can't be a SwiftPM package suite
like the rest of the tree.

- **Two files, two levels.** `IntentSupportTests` is fast, offline, unit-level
  coverage of the pure logic (`StationEntity` ↔ `Station` round-trip, the schema
  enums' `caseDisplayRepresentations`, `IntentStationCache` dedup/capacity) via
  `@testable import ShoutKit`. `AppIntentsPathwayTests` uses `AppIntentsTesting`'s
  `IntentDefinitions` to drive `StationEntityQuery.suggestedEntities()` through
  the real system pathway (curated seed → suggestions), the way Siri/Spotlight
  would.
- **Deliberately no `perform()` test of `PlayStationIntent`.** Its `perform()`
  starts real playback (audio session + network stream); asserting on the
  entity-query pathway exercises the framework without those side effects. The
  pathway test also avoids the live `entities(matching:)` directory search so it
  stays deterministic/offline.
- **Runs on a host, not `swift test`.** The target is added to
  `ShoutKit.xctestplan` alongside the package suites. It builds green
  (`xcodebuild build-for-testing`), but this sandbox and the current CI can't run
  app-hosted xctest (the xctest agent SIGSEGVs; see [[shoutkit-ci-xcode27]]), so
  the suite is validated by **Cmd+U in Xcode** for now — not wired into CI.
  Confirmed green via Cmd+U on 2026-07-18.
- **Caveat:** `IntentDefinitions` looks types up by string identifier (defaults
  to the Swift type name, e.g. `"StationEntity"`). Compiles regardless; if the
  pathway test traps at runtime, the identifier string is the thing to adjust.

## 2026-07-18 (iOS 27 MediaSession now-playing selection)

`PlaybackController`'s production convenience init now selects the system
now-playing surface by OS version instead of hardcoding the legacy path.

- **`makeSystemNowPlayingCenter()` returns `MediaSessionNowPlayingCenter` on
  iOS 27+ (typed `MediaSession` + `RadioContent`) and `NowPlayingCenter` on
  iOS 26** (the `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` bridge). The
  `MediaSessionNowPlayingCenter` implementation already existed; this wires it in.
- **Availability-based, not a feature flag.** The 0.3.0 plan calls for exactly a
  `#available(iOS 27, *)` switch with a "one-line revert" escape hatch, so the
  fallback is deleting the `#available` branch — not a runtime toggle. Both
  implementations sit behind `NowPlayingPresenting`, so the controller, its tests,
  and the fakes are untouched.
- **Guarded by `#if canImport(NowPlaying)`** so the package still builds on SDKs
  without the framework (it collapses to legacy). Verified `NowPlaying.framework`
  is present in the iphoneos 27 SDK, so the branch is live on device.
- **On-device parity verified** on an iPhone 17 Pro (iOS 27), 2026-07-18: lock
  screen, Control Center, Dynamic Island transport (incl. landscape), artwork,
  station switch, and ad-break suppression all behaved with no regressions vs.
  the legacy path. This completes the 0.3.0 MediaSession workstream.

## 2026-07-18 (list artwork prefetch)

Browse/Search station lists now prefetch upcoming rows' artwork so scrolling
doesn't stall on a cold decode as each row appears.

- **Warmed the existing custom pipeline, not a formal list-prefetch API.**
  Artwork loads through `ArtworkThumbnailLoader` (ImageIO downsample →
  `NSCache`), not `AsyncImage`, so the stall to remove is the per-row
  fetch+decode, and the fix is warming that cache ahead of time. A new
  fire-and-forget `ArtworkThumbnailLoader.prefetch(_:maxPixelSize:)` does exactly
  that; rows call `.prefetchStationArtwork(after:in:)` (DesignSystem) with a
  6-row look-ahead from each row's `onAppear`.
- **Added in-flight coalescing (a small actor) to the loader.** Without it, a
  prefetch and the row's own `.task` for the same artwork would race into two
  fetch+decodes. Callers now share one in-flight `Task` per cache key; the entry
  is dropped on completion so a later miss re-fetches rather than pinning a stale
  result (the decoded bitmap lives in the `NSCache`, not the coalescer).
- **Shared the decode size so prefetch and row hit the same cache key.**
  `StationArtworkView.listSize` (56 pt) is now the single source of truth for the
  row artwork size and the prefetch's `maxPixelSize` (× display scale), so a
  prefetch can't miss the row's later request over a size mismatch.

## 2026-07-18 (Home Screen quick-play widget)

A configurable Home Screen widget that plays a chosen favorite in one tap.

- **The widget opens a `shoutkit://station?...&autoPlay=1` deep link via
  `.widgetURL`, not a headless `AudioPlaybackIntent`.** The deep link already
  carries the full station snapshot and is the same path Shortcuts/notifications
  use, so playback needs no shared audio stack in the extension — it reuses
  `StationLink` + `StationLaunchRouter` + `RootView.handle(_:)` unchanged. This
  matches the watch complication's `widgetURL` pattern. A `Button(intent:)`
  headless play was rejected for v1 because it would drag `AppDependencies` (the
  whole app graph) into the widget process.
- **Configuration is `AppIntentConfiguration` with a `WidgetConfigurationIntent`
  (`SelectFavoriteStationIntent`) + a lightweight `FavoriteStationAppEntity`**,
  per the roadmap's "favorite station as an intent-configured parameter." The
  entity/query read *only* the App Group snapshot, so the picker resolves without
  the app's dependency graph. Unset selection falls back to the first favorite.
- **The app mirrors favorites to the widget through the existing App Group
  (`group.com.cascadiacollections.shoutkit`)**, via a new dependency-free
  `QuickPlayFavoritesStore` in `NowPlayingActivityCore` (already linked by both
  the app and the widget), mirroring `LiveActivityArtworkStore`'s
  container/override pattern. `RootView` republishes on any favorites change
  (`onChange` over a station-id signature, so add/remove/**reorder** all trigger)
  and reloads the timeline via `WidgetCenter`. The app target gained a direct
  `NowPlayingActivityCore` product dependency (it previously linked only
  `NowPlayingActivityKit`).
- **v1 renders a glyph + name/genre, no artwork.** Home Screen widgets can't
  fetch remote images, and staging per-favorite PNGs (as the Live Activity does
  for the single current track) isn't worth it for a station picker yet.

## 2026-07-16 (watchOS companion app)

- Chose **watch-native streaming** for the first Apple Watch companion instead of relaying audio from the phone. `PlaybackController` already only depends on the `AudioOutput` and `NowPlayingPresenting` seams, so a tiny watch-local `AVPlayer` engine reuses the same controller and `RecentStation` snapshots without adding a WatchConnectivity relay protocol or a paired-device availability state machine.
- Kept the watch surface intentionally narrow: a recent-stations list, a minimal now-playing controller, and a complication that deep-links straight into "play last station." That keeps the first implementation small while making the watch's audio-ownership model obvious in code.

## 2026-07-16 (Siri warmupAudioQueue prewarm hook)

The deferred `AppSchema.audio.warmupAudioQueue` hook from the 2026-07-15
latency pass is now implemented. A public iOS 27 beta doc mirror confirmed the
schema's shape: **`audioEntity` + `playbackAttributes` as inputs, returning
`WarmupAudioQueueResult` as the value** — notably *without* the
`queueLocation`/`warmupAudioQueueResult` parameters that belong to
`.audio.playAudio`.

- **`WarmupRadioAudioQueueIntent` resolves the target station through the
  app's existing `RadioDirectoryProviding.streamEndpoint(for:)` path before
  prewarming**, instead of trusting the snapshotted `preferredStreamURL`
  blindly. That keeps Siri warmup aligned with the same stream-endpoint logic
  playback already uses (preferred URL short-circuit where available, directory
  resolution where not).
- **The intent reuses `StationConnectionPrewarmer` directly** and returns a
  payload-free `WarmupAudioQueueResult`. The prewarm effect is OS-level DNS/TCP/TLS
  warmth, not queue state stored in-app, so `PlayRadioAudioIntent` still
  doesn't need to inspect the optional `warmupAudioQueueResult` it receives
  later.

## 2026-07-15 (network/playback latency pass)

A latency audit of the directory HTTP stack and the tap-to-audio path drove a set
of OS-level optimizations. Findings that shaped the work: favorites/recents
already skip the directory round-trip via snapshotted `preferredStreamURL`; the
biggest remaining costs were cold-start directory serialization + a 12s mirror
timeout, endpoint re-resolution on every reconnect, and no connection prewarming
of the user's own stations.

- **Interactive `RetryPolicy` (5s timeout) for Radio-Browser discovery**, vs. the
  12s `.default` kept for SHOUTcast/background. A dead first mirror now fails
  over ~2.4× sooner. Timeout is per-request (`URLRequest.timeoutInterval`), so
  this needed only a new policy constant, not session surgery.
- **Latency-tuned shared `URLSession`** (`URLSessionHTTPTransport.interactiveConfiguration()`):
  `waitsForConnectivity = false` (fail fast into our own mirror/retry logic
  instead of URLSession silently parking a request) + `networkServiceType =
  .responsiveData`. Installed as `shared` at bootstrap; Debug's Pulse session is
  built from the same config so behaviour matches Release.
- **Concurrent top-stations + genres** in `BrowseViewModel.refresh()` via
  `async let` (were serial). Genres stays non-fatal (folded into a returned
  optional error); top-stations stays fatal. Un-awaited genres auto-cancels on
  the empty/failure paths.
- **Reconnect reuses the resolved endpoint** (`PlaybackController.resolvedEndpoint`)
  instead of re-running resolution each backoff attempt — matters for SHOUTcast
  (`.pls` fetch+parse) and byuuid re-resolves. Cleared on a fresh `play(_:)` so a
  new choice always re-resolves.
- **`RecentStation.playCount`** (additive migration, like `isHiddenFromListenNow`)
  incremented in `logRecent`'s existing-match branch. `playedAt` is overwritten
  each play, so there was previously *no* frequency signal — only recency. This
  gives a real "well-trafficked" ranking.
- **Launch-time connection prewarming** (`StationConnectionPrewarmer`, in Playback):
  opens and immediately tears down an `NWConnection` to the top few
  most-played/favorited stations' hosts (`LibraryStore.prewarmStreamURLs`),
  priming the process-wide DNS cache + TCP/TLS path state so the first tap skips
  the cold handshake. Connection-level, not an HTTP GET — costs a handshake, not
  a download; the OS DNS warmth is shared with AudioStreaming's own socket. Gated
  behind a new internal `prewarmStations` flag, default off, fired as a detached
  utility task alongside the existing Spotlight-index task.
- **Deferred: the Siri `warmupAudioQueue` schema intent.** The platform-native
  "prewarm before playAudio" hook exists in `AppSchema.audio`, but its required
  shape is undocumented (would need the same build-error iteration playAudio
  took), and Siri routing itself isn't yet confirmed working on-device. The
  launch prewarmer delivers the same DNS/TLS warmth without that risk; revisit
  the Siri intent once routing is verified.

## 2026-07-15 (iOS 27 floor raised; real `AppSchema.audio` Siri domain adopted)

Reverses the 2026-07-06 entry below: the deployment floor is now **iOS 27**
(was 26) across every package (`Package.swift` platforms + `swift-tools-version:
6.4`, since `.iOS(.v27)` requires it) and the app target
(`IPHONEOS_DEPLOYMENT_TARGET`). Reason: a bare "Hey Siri, play ⟨station⟩
radio" (no "on ShoutKit") wasn't resolving — `StationEntity: IndexedEntity`
makes Siri able to look a station up once it knows to ask ShoutKit, but
doesn't register ShoutKit as a *radio* content provider, so an app-name-free
utterance had no reason to route here over Apple Music. That registration
requires the real `AppSchema.audio` domain schema, which is iOS-27-only.

Also worth noting: by the time of this change, `AssistantSchema`/`@AssistantEntity`/
`@AssistantIntent` (what the 2026-07-06 entry deferred to) are themselves
`@available(*, deprecated, renamed: "AppSchema")` in the iOS 27 SDK — superseded
by `@AppEntity(schema:)`/`@AppIntent(schema:)` before this project ever adopted
them. So this is a fresh implementation against the current API, not a
revival of the deferred one.

- **`StationEntity` adopts `@AppEntity(schema: .audio.liveRadioStation)`**,
  replacing the plain `AppEntity` conformance. The schema requires two
  additional properties beyond what `IndexedEntity` needed: `title: String`
  (computed from the existing `name`) and `providerName: String?` (`nil` —
  ShoutKit doesn't track a station's parent network separately from the
  station itself).
- **Two separate `PlayStationIntent`-shaped intents, not one**, because
  `AppShortcutPhrase` can only bind plain `AppEntity`/`AppEnum` parameters —
  confirmed by an explicit framework diagnostic ("'AppEntity' and 'AppEnum' are
  the only allowed types for 'audioEntity'"), not just a Swift type-inference
  gap. `PlayStationIntent` (unchanged in shape) keeps powering the existing
  "Play ⟨station⟩ on ShoutKit" `AppShortcut` phrase. The new
  `PlayRadioAudioIntent` adopts `@AppIntent(schema: .audio.playAudio)` and is
  deliberately absent from every `AppShortcut` phrase — its only job is
  passive registration, so the system's own "Play Audio" Siri domain can
  dispatch a bare, app-name-free utterance straight to it via
  `StationEntity`'s Spotlight index. Both intents call the same
  `PlaybackController.play(_:)`.
- **`audioEntity: AudioItem`, a `@UnionValue` enum with one case
  (`.liveRadioStation(StationEntity)`)**, not `StationEntity` directly — the
  schema's `audioEntity` parameter is a fixed union across every content kind
  the `.audio` domain supports (songs, albums, podcasts, live radio, …); a
  `@UnionValue` enum is how a single app opts into just the cases it plays.
  Confirmed by compiler diagnostic listing the full `Schema<SongEntity> |
  Schema<AlbumEntity> | … | Schema<LiveRadioStationEntity> | …` union — trying
  to pass `StationEntity` there directly fails to typecheck.
- **`queueLocation`, `warmupAudioQueueResult`, `playbackAttributes` all take
  the schema's "nothing to report" value** — required parameters for apps
  with a real play queue; ShoutKit has none (switching stations is immediate
  replacement, not enqueueing). Their exact required shape (which fields must
  be `Optional`, which must not; that `playbackAttributes` is `Set<Enum>` not
  a bare enum; the extra enum cases each schema enum requires, e.g.
  `PlaybackAttributes` needs `.shuffle`/`.repeat` even though ShoutKit only
  ever uses `.none`) came from iterating on real `xcodebuild` macro-expansion
  diagnostics against the on-disk iOS 27 SDK, not from documentation — this
  schema surface has no public reference material yet.

## 2026-07-13 (dependency-review follow-ups)

Follow-ups from an adversarial review of the three-dependency branch, applied
before merge:

- **Dependabot's swift entries collapsed into one multi-directory block**
  covering every manifest with a remote dependency (the old three-entry list
  predated Playback/BrowseFeature/SearchFeature/DebugSupport gaining remote
  deps and its "only three packages" comment had gone stale). A `groups`
  config bundles Factory bumps into one PR: Factory is `exact`-pinned in four
  manifests, and an ungrouped bump of a single one would leave SwiftPM with
  unresolvable conflicting exact pins.
- **swift-numerics attributed** in `THIRD_PARTY_LICENSES.md` and the in-app
  Licenses screen. It's transitive-only (swift-algorithms' `RealModule`), but
  the project's stated policy is to attribute what's in the shipped dependency
  graph, and every other transitive (ogg/vorbis) already was.

## 2026-07-13 (Pulse adopted for debug-only network inspection)

- Adopted **Pulse 5.2.3** (MIT, `kean/Pulse`) for debug network inspection —
  the `Pulse` product only (not `PulseProxy`'s method-swizzling auto-logger, nor
  `PulseUI`'s viewer — no in-app UI was added this pass, see below). Listed
  under `THIRD_PARTY_LICENSES.md`'s dev-tools section, not the runtime table,
  since by design it never ships in Release. Debug builds *do* carry it — and
  testers receive Debug builds, and MIT's notice requirement has no
  debug-builds exemption — so the in-app Licenses screen shows a
  `#if DEBUG`-gated Pulse entry.
- Pulse is declared only by **`Packages/DebugSupport`**, a small app-side
  package that only the app target links — never by RadioDirectory or any other
  reusable MIT package, so external consumers of those packages don't fetch or
  build inspection tooling just to use a directory client. Every Pulse
  reference lives in one file, `DebugSupport/DebugNetworkInspection.swift`,
  wrapped end to end in `#if DEBUG` (including the `import Pulse` itself) —
  auditing "is Pulse entirely gated" only requires reading that one file. The
  seam it uses: `URLSessionHTTPTransport.installSharedSession(_:)` (first
  install wins, and it must precede the first network call —
  `AppDependencies.bootstrap()` calls it first thing), which swaps the session
  behind `URLSessionHTTPTransport.shared` for one wired with
  `URLSessionProxyDelegate`. Since Radio-Browser, SHOUTcast, and artwork
  downloads (`ArtworkLoader`, `NowPlayingCenter`) all default to that one
  shared transport, the single seam covers all of them without touching any of
  those call sites. `AlbumArtLookup`'s separate, short-timeout iTunes-lookup
  session is intentionally left alone — out of scope for "Radio-Browser and
  artwork requests."
- No in-app viewer was added (`PulseUI`'s `ConsoleView` or a Settings debug
  entry): the task's acceptance bar was the logging proxy plus a Debug/Release
  presence check, and a viewer screen wasn't asked for — logs are still
  inspectable via Pulse's remote/Mac companion tooling. Revisit if a
  discoverable in-app console turns out to be worth the added surface.
- **Correction, found the hard way**: `#if DEBUG`-gating Pulse's Swift call
  sites does *not* keep Pulse's own compiled module out of the Release binary.
  SPM's dependency graph is configuration-independent —
  `PackageDescription.TargetDependencyCondition.when` only takes
  `platforms:`/`traits:`, never a build configuration (checked directly against
  swift-package-manager's source; there's no such API at any shipped tools
  version) — so a declared `.product(...)` dependency links into every
  configuration that consumes it, regardless of whether any surviving
  (post-preprocessor) source references it. CI's first Release build proved
  this empirically: `nm` found `NetworkLogger` in the Release binary even
  though the Release compile of `RadioDirectory` genuinely had no `-DDEBUG`
  flag. A follow-up commit tried `condition: .when(configuration: .debug)` —
  that parameter doesn't exist in `PackageDescription` and doesn't compile.
  What `#if DEBUG` *does* guarantee, and what actually matters: none of
  Pulse's logging/proxy code ever runs in Release — behaviorally, it's
  identical to Pulse not being there. Its compiled-but-unreferenced module may
  still be physically present in the Release binary; achieving true binary
  absence would need Xcode-project-level linking changes beyond what a local
  Package.swift can express, which is out of scope here.
- `ci.yml`'s `build` job builds both Debug and Release against a shared
  `-derivedDataPath` (Debug/Release each get their own
  `Products/<Config>-iphonesimulator` output, but package resolution and
  unchanged modules are reused across the pair) and `nm`-checks each binary
  for a Pulse-specific symbol (`NetworkLogger`): a hard failure if it's
  *missing* from Debug (that would mean the proxy isn't actually wired up),
  and a non-blocking, informational report either way for Release (per the
  correction above, present-but-unused there is expected, not a bug). Bumped
  the job's timeout accordingly (30 → 45 min) since building the app twice
  roughly doubles its wall time.

## 2026-07-13 (AudioStreaming adopted as the playback engine)

- Adopted **AudioStreaming 1.4.4** (MIT, `dimitris-c/AudioStreaming`) as the concrete
  `RadioPlaybackEngine` (see the 2026-07-13 Factory entry below), backed by its
  `AudioPlayer` (`AVAudioEngine`). `Container.radioPlaybackEngine`'s default now
  constructs `AudioStreamingPlaybackEngine` on iOS; `PlaybackControllerPlatform`'s
  production initializer resolves it via `Container.shared.radioPlaybackEngine()`
  instead of constructing `AVPlayerAudioOutput()` directly. `AVPlayerAudioOutput`
  itself was **deleted** rather than kept as an unwired shadow engine: two
  parallel engines with duplicated session/interruption handling is silent rot,
  tests and previews already run on `StubRadioPlaybackEngine`, and git history
  keeps it recoverable if an AVPlayer fallback is ever genuinely wanted.
- AudioStreaming transitively pulls `ogg-binary-xcframework` and
  `vorbis-binary-xcframework` (both BSD, Xiph.org) for its Ogg Vorbis codec
  support — unavoidable if adopting AudioStreaming at all, since that codec
  bridge is baked into the library rather than an optional add-on. Recorded in
  `THIRD_PARTY_LICENSES.md` and the in-app Licenses screen alongside
  AudioStreaming itself. One accepted tradeoff, noted for honesty: these are
  *prebuilt binaries*, so the integrity chain is closed (manifest revision →
  SHA-256 checksum → artifact, locked by `Package.resolved`) but provenance is
  trust-based — we trust sbooth's builds were produced from the Xiph sources
  they claim. A small reproducibility concession for a FOSS project; rebuild
  from Xiph source ourselves if it ever stops being acceptable.
- AudioStreaming doesn't touch `AVAudioSession` itself (by design, per its own
  source), so `AudioStreamingPlaybackEngine` owns session activation and
  interruption/route-change handling directly — mirroring `AVPlayerAudioOutput`
  line for line — rather than assuming the library does it. Both stay behind
  `#if canImport(UIKit)`, and the `Playback` package's SPM manifest mirrors that
  gate with `condition: .when(platforms: [.iOS])` on the AudioStreaming product
  dependency, so the mac host test job (`swift test`) never fetches or links it.
- Added a conservative `SongTitleFilter` (pure, in `Playback`) applied in
  `PlaybackController.handleTrackInfo` before a parsed ICY track reaches
  `nowPlaying`/`onTrackHeard` — shared by both playback engines, since both feed
  `ICYMetadataParser` output through the same call site. Rejects only on a
  positive junk signal (a URL, the station's own name, promotional copy, or a
  bare single-word ID token); everything else passes through. A rejected update
  is dropped, not blanked, so the previous good track stays on screen.
- Added `StationNameFormatter` (`RadioDirectory`) to clean up station names at
  ingestion — Radio-Browser and SHOUTcast names arrive with underscores standing
  in for spaces and bracketed/parenthesized clutter tags (`[HD]`, `(128k)`).
  Applied once, at `RadioBrowserDirectoryClient.station(from:)` and the
  SHOUTcast SAX mapping, so every consumer (search, browse, the song-title
  filter's station-name comparison) sees the same clean name.

## 2026-07-13 (Factory adopted for dependency injection)

- Adopted **Factory 3.3.1** (MIT, `hmlongco/Factory`) as a `Container`-based DI seam ahead of the
  playback-engine swap (AudioStreaming) and debug network logging (Pulse) landing in later phases —
  both need a registration point that can flip from a stub/AVPlayer default to a real implementation
  without touching call sites. Import is `FactoryKit` (the module was renamed from `Factory` in the
  3.x line); the package itself is still named `Factory`.
- Two registrations so far: `Container.radioDirectory` (`RadioDirectory` package, defaults to
  `RadioBrowserDirectoryClient()`) and `Container.radioPlaybackEngine` (`Playback` package, defaults
  to a new `StubRadioPlaybackEngine` — a placeholder for the `AudioStreaming`-backed engine landing
  next). Both use `.onPreview`/`.onTest` to force `PreviewRadioDirectory`/the stub in non-production
  contexts, and `.scope(.singleton)` so the app shares one instance.
  `AppDependencies.bootstrap()` overrides `radioDirectory` with the real decorated (preferred +
  caching) instance via a free function (`registerProductionRadioDirectory`) kept in the
  `RadioDirectory` package, so the app target itself never needs to import `FactoryKit` directly.
- `BrowseViewModel`/`SearchViewModel` now default their `directory` initializer parameter to
  `Container.shared.radioDirectory()` instead of direct instantiation (`PreviewRadioDirectory()` /
  a required parameter). `RootView` no longer threads a `directory` instance through three call
  sites — Factory resolves it instead.
- `RadioPlaybackEngine` (`Playback` package) is `AudioOutput` with no new requirements — a marker
  protocol so a future concrete engine can satisfy both the existing `PlaybackController` seam and
  the new Factory registration. `PlaybackControllerPlatform`'s production wiring still constructs
  `AVPlayerAudioOutput()` directly for now; the swap to a Factory-resolved engine happens once a
  real implementation exists.

## 2026-07-12 (App Intents entity schemas + typed playback failures)

Two 0.3.0 workstream items, picked up together since both mirror an existing pattern
(`RadioDirectoryError`) rather than introducing a new one:

- **`StationEntity: IndexedEntity`, not the `AssistantSchema` macros.** The 0.3.0 plan's
  Workstream B calls for "entity schemas so Siri discovers app content through Spotlight's
  semantic index." The iOS 27 SDK has two distinct mechanisms here: `IndexedEntity`
  (`attributeSet: CSSearchableItemAttributeSet`, available since iOS 18) and the new
  `@AssistantEntity`/`@AssistantIntent` macros, which generate conformances gated
  `@available(iOS 27, *)` and expose a purpose-built `LiveRadioStationEntity` schema under
  `AppSchema.audio`. The macro route is the more complete answer, but its generated extension
  is `@available(iOS 27, *)` on the type itself — attaching it to `StationEntity` would make the
  type (used as a plain `@Parameter` on `PlayStationIntent`, which must build for the iOS 26
  floor) unavailable below iOS 27. Raising the deployment target for this is explicitly out of
  scope per the 2026-07-06 iOS 27 adoption entry. So this change adopts only `IndexedEntity`
  (buildable at iOS 26) and pushes known stations into Spotlight's index via
  `CSSearchableIndex.indexAppEntities(_:)`, called once per launch from
  `AppDependencies.bootstrap()`. Revisit the `AssistantSchema` macros when the floor moves to
  iOS 27.
- **Indexed once per launch, not on every favorite/recent change.** `StationEntityQuery`
  already has `knownStations()` (favorites → curated → recents → the Shortcuts search cache);
  `indexKnownStationsForSpotlight()` reuses it verbatim. A favorite toggled mid-session doesn't
  re-index until the next launch — accepted for v1, same "best effort" category as the
  album-art lookup's next-track-only lock-screen catch-up (2026-07-09 entry).
- **`PlaybackError` mirrors `RadioDirectoryError`'s shape exactly**: `Error, Equatable,
  LocalizedError, Sendable`, an `errorDescription`, and an `isRetryable`. `PlaybackState.failed`
  and `AudioStatus.failed` moved from a raw `String` to this type (`.streamFailed(String)` for
  the one `AVPlayerItem` KVO failure site, `.directory(RadioDirectoryError)` for endpoint
  resolution failures). This closes the last stringly-typed error surface named in the 0.3.0
  plan (Workstream E) and lets `handleResolutionFailure` ask `playbackError.isRetryable`
  instead of inline-checking `(error as? RadioDirectoryError)?.isRetryable == false`. No call
  site destructures the associated value except `NowPlayingView`'s status badge (now reads
  `error.errorDescription`) and the Playback test suite (literal strings wrapped in
  `.streamFailed(...)`); every other consumer (`MiniPlayerView`, `StationRow`/`StationCard`/
  `StationCarousel`/`SpotlightCard`, the Live Activity coordinator) only pattern-matched the
  case, not the payload, so `Equatable` conformance was the only requirement carried forward.

## 2026-07-11 (iPadOS support)

The project has always *launched* on iPad — `TARGETED_DEVICE_FAMILY` was already `1,2`, the app's
Info.plist declares all four iPad orientations, and `UIRequiresFullScreen` was never set, so Split
View / Stage Manager resizing worked from day one — but every surface rendered as a stretched
phone layout. Closing that gap is UI adaptation, not project surgery:

- **`.tabViewStyle(.sidebarAdaptable)` on the root `TabView`, not a `NavigationSplitView`
  rewrite.** On iPhone the style resolves to the same bottom tab bar as before; on iPad it yields
  the Apple Music-style sidebar with the system's own toggle back to a top tab bar. A
  `NavigationSplitView` would have duplicated the tab structure behind a size-class branch and
  left `tabViewBottomAccessory` — the mini-player's home, and the reason the accessory must stay
  structurally attached (see RootView's comment) — without a host.
- **Station rows flow into an adaptive `LazyVGrid` (`ShoutKitLayout.stationColumns`, 288–640 pt
  columns) rather than branching on `horizontalSizeClass`.** `GridItem(.adaptive(...))` derives
  the column count from actual available width, so one code path covers iPhone (one column), iPad
  Split View (one–two), and full-screen iPad (two–three) — including Stage Manager's arbitrary
  window widths, which a two-case size-class branch mishandles by design. The 288 pt floor is the
  narrowest supported pane (a 320 pt Split View / Slide Over window minus the screens' 16 pt
  horizontal padding): an adaptive grid honors its minimum even when the container is narrower,
  overflowing instead of shrinking, so a larger minimum would clip rows there (Copilot caught
  this on the PR — the first draft used 330 pt). The 640 pt ceiling stops a lone row on a wide
  window from parking the play affordance arm's-length from the station name. The columns are a
  shared DesignSystem token so Listen Now, Browse, and Search can't drift apart.
- **Deliberately left alone**: `LibraryView` stays a `List` — its edit mode drives drag-to-reorder
  and swipe-to-delete (the reorderable-favorites feature), which `LazyVGrid` has no counterpart for,
  and inset-grouped lists are already at home at iPad widths. The Now Playing surface stays a
  sheet: `presentationDetents([.large])` is a no-op on iPad, where the system presents it as a
  centered page sheet, which the artwork-centered layout fits comfortably. The widget target
  already declared both device families, so widgets needed nothing.

## 2026-07-11 (background battery hygiene, follow-on)

A "runs hot while streaming" report against the app whose dominant mode is hours of *background*
audio (screen locked). A second audit — this time of the streaming/audio layer, not just resource
retention — plus the one UI change it surfaced:

- **The audio/network layer had no additional heat source.** `AVPlayerAudioOutput` uses the
  correct `.playback`/`.default` session, its `automaticallyWaitsToMinimizeStalling` is already
  bounded by the 90s stall ceiling, ICY metadata is push-delivered (not polled), and status is
  KVO/event-driven. `PlaybackController`'s timers are all one-shot, reconnect is bounded (3
  attempts, 2/4/8s backoff) with a budget guard, and `NowPlayingCenter` updates fire only on
  discrete transitions. Nothing here was changed — this bullet records that the layer was audited
  and cleared, so a future "battery" report doesn't re-tread it.
- **`PlayingIndicator` now rests when the scene isn't foreground-active.** The 3-bar equalizer is
  the app's only continuous UI render loop — a `TimelineView(.animation(minimumInterval: 0.12))`
  recomputing `sin()` bar heights ~8×/second. It already self-paused on `!isAnimating` and Reduce
  Motion but not on `scenePhase`, so it kept doing ~8 fps re-layout during backgrounded/locked
  playback where nothing is visible. Folding `scenePhase != .active` into a single `isPaused`
  gate (shared by the `TimelineView` `paused:` argument and the `barHeight` rest guard) drops that
  to zero off-screen work; SwiftUI re-evaluates `body` on the environment change, so the bars
  settle to their resting height instead of freezing mid-swing. Foreground behavior is unchanged.
  This is the first `scenePhase` use in the app — explicit hygiene in the same spirit as the
  2026-07-10 paused-player release, rather than trusting the OS to suspend the timeline implicitly.

## 2026-07-10 (CI/CD hardening ahead of a production release)

SwiftLint `--strict` was the only automated code-quality gate; the rest of CI just built and ran
tests. Rounding this out before a real release, using the GHE-hosted tooling that's already free
for this repo rather than reaching for a paid third-party service:

- **CodeQL (Swift): no custom workflow needed.** A first attempt added a `codeql.yml` with
  `build-mode: manual` mirroring the `build` job's `xcodebuild` invocation. Its first real run
  failed at upload: *"CodeQL analyses from advanced configurations cannot be processed when the
  default setup is enabled"* — this repo already has GitHub's zero-config **default setup** for
  code scanning turned on at the repo/org level, and GitHub refuses to run both an advanced
  (checked-in-workflow) configuration and default setup at once. Since default setup already covers
  Swift, the custom workflow was removed rather than filing a settings change to disable default
  setup for a marginal customization win.
- **Dependency Review action, not a standalone license-scanner dependency**: it reads the same
  policy already written down in `THIRD_PARTY_LICENSES.md` (GPL/LGPL/AGPL rejected) and runs only
  on the PR diff, so it costs nothing on an unshared runner and doesn't need a config file of its
  own to drift out of sync with the license table.
- **Dependabot `swift` ecosystem, scoped to the three packages with a remote dependency**
  (RadioDirectory, DesignSystem, LiveActivity): the rest of `Packages/*` resolve exclusively
  through local `.package(path:)` references, so a Dependabot entry for them would just poll for
  nothing every week.
- **`swiftformat --lint` via Homebrew, not a pinned portable binary like SwiftLint**: SwiftLint's
  release ships a portable zip; SwiftFormat's doesn't, and this repo has no existing local pin for
  it (`CONTRIBUTING.md` only pins SwiftLint). Homebrew is preinstalled on GitHub-hosted macOS
  runners and is nicklockwood/SwiftFormat's own documented install path — adding a version pin for
  a tool nobody pins locally would be gate-keeping without a matching local workflow to keep it
  honest.
- **`swiftformat --lint` is `continue-on-error: true` for now, unlike SwiftLint.** First CI run
  found 58/90 files don't conform (mostly `indent` and `wrapMultilineStatementBraces`) — the tree
  has never had it enforced, unlike SwiftLint (which was already clean when `--strict` landed, per
  the 2026-07-03 entry below). Fixing that needs a byte-exact `swiftformat` run from an actual
  toolchain to avoid hand-introducing subtly-wrong formatting across 58 files; this environment has
  neither Xcode nor a Linux Swift toolchain available (`download.swift.org` is blocked by egress
  policy). CI surfaces the drift without blocking merges until someone with a real toolchain runs
  `swiftformat ShoutKitApp Packages` as a one-time reformat commit — drop `continue-on-error` once
  that lands.
- **Release automation stops at drafting a GitHub Release from `CHANGELOG.md`.** A tag push
  extracts the matching `## [X.Y.Z]` section and fails loudly if it's missing (i.e., someone
  tagged before cutting the changelog over from `[Unreleased]`). It deliberately does **not**
  build, sign, or upload to TestFlight — this repo has no Apple signing credentials configured, and
  faking that pipeline with `CODE_SIGNING_ALLOWED=NO` (as the CI `build` job does) would produce an
  archive nobody can install. Wiring up notarized/signed builds is a follow-up once distribution
  certificates exist as repository secrets.
- **Branch protection, required status checks, and secret-scanning push protection are explicitly
  out of scope for this change.** They're repository/organization settings, not files this repo's
  git history can carry, and the GitHub tooling available to this session has no branch-protection
  or repository-settings endpoint exposed — only content/PR/issue operations. Recommended for an
  org admin to apply directly: require the `build`, `host-tests`, and `lint` checks (plus CodeQL
  once it has a green run) before merging to `main`, and enable secret-scanning push protection
  under repo Settings → Security.

## 2026-07-10 (Live Activity artwork via App Group hand-off)

The lock screen / Dynamic Island Live Activity shipped text-only (2026-07-03 entry below) on the
reasoning that Live Activity views can't fetch network images. That's true, but it isn't the whole
story: a view *can* render a local file, so the app can produce the bitmap and hand it over. The
Now Playing screen, mini-player, and system (`MPNowPlayingInfoCenter` / `MediaSession`) surface all
show artwork; the Live Activity was the one place that didn't. This reverses the scope-out.

- **The bytes travel through a shared App Group container, not the content state.** ActivityKit
  caps `ContentState` at ~4 KB, nowhere near a bitmap, and the state is serialized on every update.
  So `NowPlayingActivityCore.LiveActivityArtworkStore` owns a directory in
  `group.com.cascadiacollections.shoutkit` (entitled on both the app and the widget target); the
  app writes a downsampled PNG there and the content state carries only a short `artworkToken`. The
  widget resolves the token back to a file URL and renders it with `UIImage(contentsOfFile:)`.
- **Token = FNV-1a of the source URL, not `Hashable`.** `Hasher` is seeded per launch, so its
  output can't be a stable key shared across the app and widget processes. FNV-1a over the URL
  string is deterministic and filesystem-safe, and the single-item cache makes collision risk moot.
- **The coordinator observes `albumArtURL` too.** It already followed `state` and `nowPlaying`; a
  third `Observations` stream on the controller's resolved album art lets the widget's artwork catch
  up asynchronously exactly like the lock screen does — effective URL is album art when present,
  else the station's own art. The download/downsample/stage all run off the main actor (mirroring
  `NowPlayingCenter`'s ImageIO downsampler); only the tiny state mutation and re-push are on-main.
- **`.noFileProtection` on the staged file.** The Live Activity renders on the lock screen while the
  device is locked, and the default protection class would make the file unreadable exactly then.
  Cover art isn't sensitive. The store keeps only the current track's file (`purge(except:)`), so
  the container never grows.
- **Simulator/CI-safe.** App Group entitlements work on the simulator without a provisioning profile,
  so the `CODE_SIGNING_ALLOWED=NO` iOS-simulator build in CI is unaffected. On-device rendering still
  needs a real provisioning profile with the group enabled (device-only verification, as before).

## 2026-07-10 (bounded auto-reconnect for dropped streams)

Live radio drops for transient reasons — a tunnel, a cell handoff, a flaky AP — far more often
than permanent ones, but the two paths that ended playback (the 90 s stall ceiling and a
mid-play `AVPlayerItem` failure) both gave up immediately: park as `.paused` / surface `.failed`
and wait for a user tap. `PlaybackController` now attempts a bounded, backed-off reconnect
before either give-up. Prompted by an evaluation of FRadioPlayer (MIT), whose `NWPathMonitor` +
`StallRecovery` ladder was the one capability our stack lacked; the rest of FRadioPlayer would
have been a regression against our multi-dialect ICY parser and strict-concurrency model, so we
ported the idea, not the code.

- **Reconnect is orchestration, so it lives in `PlaybackController`, not `AVPlayerAudioOutput`.**
  A "reconnect" for live radio is just a fresh `startPlayback` — there's no position to resume —
  so the controller (which already owns restart) drives it and the output layer stays a dumb,
  fakeable AVPlayer wrapper. Both the attempt budget (`maxReconnectAttempts`, default 3) and the
  base delay (`reconnectBaseDelay`, default 2 s → 2/4/8 s exponential backoff) are injected like
  the existing hygiene timeouts, so tests use a small budget and millisecond delays; there is no
  user-facing setting.
- **The budget resets on a successful `.playing` and on a user `play()`, never inside the
  reconnect path.** `startPlayback` gained an `isReconnect` flag that guards *both* the
  attempt-counter reset and the `nowPlaying`/`albumArtURL` clear: resetting the counter on a
  retry would refill the budget every attempt and loop forever, and clearing metadata would drop
  the last-known track off the lock screen mid-reconnect. A reconnect holds `.buffering` so rows
  keep spinning and ICY repopulates the track on success.
- **A user pause/stop always beats a pending reconnect.** `pause()` and `stop()` cancel the
  reconnect timer up front — otherwise a stream the user just stopped would resurrect itself when
  the scheduled retry fired. Covered by `pauseCancelsPendingReconnect`.
- **Reachability-gated reconnect (fire immediately when the network returns, instead of waiting
  out the backoff) is deliberately deferred.** It's the other half of FRadioPlayer's edge and
  wants a small `NWPathMonitor` wrapper injected behind a closure so the fake output stays
  network-free; the bounded backoff is useful on its own and ships first.
- **`PlaybackController`'s internal wiring moved to `PlaybackController+Internals.swift`.** The
  reconnect code pushed the file past the 400-line `file_length` limit (CI runs
  `swiftlint --strict`, so warnings fail). Rather than a lint-disable, the private extension
  (stream start, status handling, album art, resource-hygiene timers) split into a sibling file,
  matching the existing `PlaybackControllerPlatform.swift` precedent. The cost: the controller's
  stored properties widened from `private` to module-`internal` (via `internal(set)` for the
  public-read state); no public API changed.

## 2026-07-10 (swift-async-algorithms adopted, revisiting the audit's rejection)

The FOSS audit below rejected swift-async-algorithms because it scored only the search
debounce, where the hand-rolled `Task.sleep` version genuinely holds its own. Re-scored
across the whole codebase, the package pays for itself — same ground rules as the audit
(Apple-maintained, Apache-2.0 with Runtime Library Exception, pinned semver `from: "1.1.5"`),
recorded in `THIRD_PARTY_LICENSES.md` and the in-app Licenses screen:

- **`removeDuplicates()` in NowPlayingActivityKit**: both observation loops in
  `NowPlayingActivityCoordinator` carried a mutable `previous` variable and a
  `where state != previous` clause — hand-rolled duplicate suppression, exactly the operator's
  job. The one behavioral wrinkle of the old code (a leading `nil` metadata value was skipped
  because `nil != nil` is false, while `removeDuplicates()` always emits the first element) is
  a no-op in practice: `nowPlayingChanged(nil)` clears already-nil state and returns before
  touching ActivityKit.
- **`debounce(for:)` in SearchFeature**: the view model now pushes trimmed queries into an
  `AsyncStream` consumed through `.debounce(for: .milliseconds(300))`, replacing the
  cancel-and-resleep task dance. Semantics preserved deliberately: clearing the query still
  resets to `.idle` synchronously in `didSet` (the empty value also flows through the stream,
  superseding any keystroke waiting in the debounce window); the spinner still appears only
  when the debounce fires, never per keystroke; and each keystroke still cancels an in-flight
  search immediately (in `didSet`, not just when the next debounced value lands) so a slow
  response for a stale query can't flash results before the new search starts.
- **Not applied to `SleepTimer`/`OneShotTimer`**: those are single one-shot delays, not
  streams of values — `Task.sleep` is the right primitive and there is nothing for an
  `AsyncSequence` operator to buy.

## 2026-07-10 (first third-party dependencies, after a FOSS audit)

The zero-dependency posture (see 2026-07-05) was revisited deliberately: audit every area a
common FOSS package could serve, adopt only where a dependency clearly beats the hand-rolled
code, and keep the count minimal. Ground rules, now written down in `THIRD_PARTY_LICENSES.md`:
GPL-3.0-compatible licenses only (MIT / Apache-2.0 / BSD — Apache-2.0 is one-way compatible
with GPL-3.0, and fine *inside* the MIT packages since the Apache code keeps its own license),
pinned stable semver (no branch refs), license recorded in that file and shipped in the in-app
Licenses screen alongside GPL/MIT.

**Adopted** (both Apple-maintained, Apache-2.0 with Runtime Library Exception, effectively
standard-library extensions — the lowest-risk dependency class that exists):

- **swift-algorithms 1.2.1** in RadioDirectory: `uniqued(on:)` replaced three private
  `deduplicated(_:)` helpers duplicated across `PreferredRadioDirectory` and
  `BundledRadioDirectory` (five call sites). Same semantics — first occurrence wins, keyed on
  lowercased name, order preserved — with the helper duplication gone.
- **swift-collections 1.6.0** in DesignSystem: `OrderedDictionary` replaced the artwork
  store's dictionary + parallel eviction-order array, deleting the two-collection invariant
  (the failure-removal path had to keep both in sync by hand). FIFO semantics unchanged.

**Evaluated and rejected** — the codebase's Apple-framework-first choices already cover these,
and each would add surface without deleting meaningful code:

- **Nuke** (MIT): the artwork pipeline is deliberately bespoke — actor-coalesced loads with
  3×3 palette extraction for the mesh backdrop, ImageIO downsample ceilings sized per surface,
  NSCache + URLCache tiers, memory-pressure purge (all documented in the two entries below).
  Nuke covers only the fetch/cache/downsample parts that already work, and none of the palette
  work; swapping it in would re-litigate the memory-bounding decisions for zero user-visible
  gain.
- **GRDB** (MIT): persistence is SwiftData behind a thin `LibraryStore` (a favorites set plus
  25 recents) with host tests. GRDB is the right call when you need SQL, migrations, or
  observation at scale — none of which this data shape has. A full data-layer migration to
  dodge a framework Apple ships is the opposite of minimal.
- **Defaults** (MIT): `SettingsStore` is ~38 lines, two keys, already type-safe and
  `@Observable`. A dependency cannot pay for itself against that.
- **swift-async-algorithms** (Apache-2.0): the only candidate site is Search's 300 ms
  debounce, which is eight idiomatic lines of `Task.sleep` + cancellation driven by an
  `@Observable` `didSet`; restructuring the view model around an `AsyncSequence` of queries
  would be more code, not less.
- **Alamofire** (MIT): URLSession already handles the entire network surface (Radio-Browser
  mirror walking, iTunes lookup, artwork); nothing here needs interceptors or multipart.
- **SwiftLint / SwiftFormat** (MIT): already adopted — configs at the root, SwiftLint pinned
  at 0.65.0 and `--strict` in CI. Dev-only tools, so they're listed in the dev section of
  `THIRD_PARTY_LICENSES.md`, not the runtime table.

Follow-up for a mac with Xcode: commit the workspace `Package.resolved`
(`ShoutKit.xcworkspace/xcshareddata/swiftpm/`) so the exact resolved versions are locked in
git, not just floored by `from:`.

## 2026-07-10 (runtime memory on older devices)

Companion to the battery audit below, same philosophy: bound resource *retention*, and lean on
platform behavior (ImageIO, NSCache, dispatch memory-pressure sources) instead of hand-rolled
bookkeeping. Bitmaps are the only meaningful runtime allocation in this app — directory models
are tiny value structs and audio buffers are ~16 KB/s — so every change targets the artwork
pipeline.

- **All artwork decodes are downsampled via ImageIO**
  (`CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize`, with
  `kCGImageSourceShouldCacheImmediately` so the decode happens off-main at load time, not
  lazily at first render). `UIImage(data:)` decodes at the server's native resolution — a
  2000×2000 favicon is ~16 MB of bitmap behind a 56 pt cell. Decoded size now scales with the
  surface: 840 px ceiling for the Now Playing pipeline (280 pt hero at 3×; the ambient
  backdrop consumes the same bitmap through a 60 pt blur, so it needs no more), cell size ×
  `displayScale` for list thumbnails, 768 px for lock-screen art. `LoadedArtwork.pixelSize`
  consequently reports the *decoded* size; every consumer decision (the 2.5× upscale cap, the
  ≥512 px blur-wash gate) resolves below the ceiling, so behavior is unchanged except for
  extreme-aspect sources (e.g. 2000×600 now downsamples to 840×252 and gets the palette mesh
  instead of the blur wash — the designed fallback for low-detail art).
- **`AsyncImage` replaced with `ArtworkThumbnailLoader`** (station rows, cards, mini-player,
  Browse spotlight). `AsyncImage` re-decodes at native size on every cell reuse and caches
  nothing but URLCache bytes. The loader still fetches through the shared `URLCache`, but
  keeps decoded thumbs in an `NSCache` (16 MB cost ceiling, costs = bitmap bytes) — chosen
  precisely because NSCache sizes itself to the device and auto-evicts under system memory
  pressure, which is the whole point on older hardware.
- **`ArtworkLoader`'s coalescing store purges on memory pressure** via
  `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])`. The FIFO-of-6
  keeps steady-state behavior; the source guarantees the worst case (six hero-sized bitmaps,
  ~17 MB) is reclaimable instead of resident forever. A dispatch source rather than
  `UIApplication.didReceiveMemoryWarningNotification`: no UIKit plumbing into an actor, and
  it also fires for pressure while backgrounded — where a music app spends most of its life.
- **Lock-screen artwork (`NowPlayingCenter`) gets a private copy of the downsampler** rather
  than a new dependency: Playback deliberately doesn't import DesignSystem (see the
  `AlbumArtLookup` decision below). The decoded artwork is retained for the whole listening
  session, usually backgrounded — exactly when jetsam hunts — so it's the single most
  important decode to bound. The iOS 27 `MediaSession` path is untouched: it hands raw bytes
  to `ArtworkRepresentation` and the system manages decoding.
- **`URLCache.shared` explicitly sized: 2 MB memory / 64 MB disk**, set in
  `AppDependencies.bootstrap()` before the first request. On a RAM-constrained device byte
  caching belongs on disk (re-decoding from disk cache is cheap next to the network); the
  larger disk tier also means artwork survives relaunch.
- **Not done, deliberately**: capping `AVPlayerItem.preferredForwardBufferDuration`. A
  128 kbps live stream buffers ~1 MB/min, so the savings are negligible while the stall risk
  on flaky radio links is real; the 90 s stall ceiling (below) already bounds pathological
  buffering.

## 2026-07-10 (background battery hygiene)

Prompted by a real-world battery report: ShoutKit at 14% of a day's battery with 2h42m
background time. The audit found no polling or periodic work anywhere (metadata is push-based,
now-playing updates are event-driven), so the fixes target resource *retention*, not activity.

- **Paused playback releases the player and audio session after 10 minutes**
  (`PlaybackController.schedulePausedRelease`). `pause()` used to keep the AVPlayerItem, its
  observers, and the active audio session alive indefinitely — pause-and-pocket held the
  `audio` background assertion for hours. Live radio has no position to preserve, so teardown
  is invisible: `state`/`nowPlaying` and the lock-screen surface are left untouched, and the
  play button routes through `resume()`'s existing `outputStarted == false` restart path.
  10 minutes matches audio-app norms; it is an init parameter, not a user setting — this is
  invisible hygiene, not behavior a listener should have to configure.
- **Stalled buffering is bounded at 90 seconds** (`scheduleStallCeiling`). AVPlayer's
  `automaticallyWaitsToMinimizeStalling` retries a stalled live stream forever; backgrounded
  with signal loss that churns the network radio with no ceiling. On expiry the stream is torn
  down and parked as **`.paused`, not `.failed`** — a stall isn't a user error, and paused
  keeps the lock screen accurate with a working play button. The controller pushes that final
  now-playing update itself, because teardown invalidates the player's KVO before pausing.
- **Internal restarts don't refire `onStationPlayed`**: `play(_:)` split into the public
  intent (fires the hook) and `startPlayback(of:)` (does the work). Resume-after-release and
  retry-after-failure are not new listening choices, so they no longer double-log recents or
  double-report the play to Radio-Browser.
- **`AlbumArtLookup` now caches definitive misses too** (supersedes the 2026-07-09
  "negative results are not cached" bullet, and resolves its recorded iTunes-budget risk).
  The distinction that matters is *definitive* vs *transient*: an HTTP 200 whose decoded JSON
  has no artwork is a catalog answer and is cached; transport errors, non-200s, and malformed
  payloads still aren't, so a network blip can't permanently suppress art. Cache capped at 256
  entries with reset-on-overflow — LRU bookkeeping isn't worth it for ~100-byte values.
- **`ArtworkLoader` coalesces per-URL work through a small actor store**: backdrop, hero, and
  tint views all request the same artwork on every track change; URLCache already coalesced
  the network fetch but each caller re-decoded the bitmap and re-ran the palette box filter.
  In-flight and completed loads now share one task per URL (FIFO-bounded at 6; nil results are
  evicted immediately so failures stay retryable). Public API unchanged.

## 2026-07-09 (Album art discovery)

- **Album art source**: iTunes Search API (`itunes.apple.com/search?entity=song&limit=1`).
  Free, keyless, widely available. Chosen over MusicBrainz (slower, more complex JSON) and
  Discogs (requires an API key). The endpoint returns `artworkUrl100`; we up-size to `600x600bb`
  by string-replacing the suffix — a documented Apple pattern.
- **`AlbumArtLookup` in DesignSystem, not Playback**: Playback is deliberately thin (it compiles
  and tests on macOS without UIKit). DesignSystem already owns `ArtworkLoader` and the rest of
  the artwork pipeline, so the lookup naturally lives there.
- **`albumArtURLProvider` hook on `PlaybackController`**: the controller resolves album art via
  an injected async closure, keeping Playback free of any DesignSystem / iTunes dependency.
  `AppDependencies.bootstrap()` wires the closure to `AlbumArtLookup.artworkURL`. The pattern
  mirrors `onStationPlayed` (existing) and means the Playback test suite never touches the API.
- **Opt-out in `SettingsStore` (Persistence), gated at the source**: `isAlbumArtEnabled`
  defaults on. The composition root's provider closure checks the setting before any network
  request (mirroring the play-reporting hook) — the toggle lives under Privacy, so opting out
  must stop the iTunes call itself, not merely hide the result. The views additionally check it
  reactively via a shared `effectiveArtworkURL` helper, so toggling takes effect immediately
  in the UI without restarting playback; the lock screen follows on the next track change
  (acceptable "best effort").
- **`NowPlayingPresenting.update()` gains `artworkURL: URL?`**: every call site passes it
  explicitly. The `NowPlayingCenter` (legacy MediaPlayer) and `MediaSessionNowPlayingCenter`
  (NowPlaying framework) both prefer the supplied URL when non-nil, falling back to
  `station.artworkURL`.
- **Positive-result cache in `AlbumArtLookup`**: transient lookup failures don't permanently
  suppress art (negative results are not cached), but a second track with the same artist/title
  (common for repeating radio formats) reuses the cached URL without a second API hit. A plain
  locked dictionary, not `NSCache` — values are ~100-byte URLs, so memory-pressure eviction
  buys nothing, and `OSAllocatedUnfairLock` is `Sendable` by construction (no reliance on
  `NSCache`'s bridging annotations).
- **Staleness guard in the album art task**: after `await provider(track)` resolves, the task
  checks that `nowPlaying.artist` and `nowPlaying.title` still match before applying the
  result — otherwise a slow network response for a previous track would overwrite the
  current track's (potentially correct) artwork.
- **Duplicate ICY pushes are deduped in `PlaybackController.onTrackInfo`**: streams re-deliver
  identical `StreamTitle` metadata (the Live Activity coordinator dedupes for the same reason).
  Without the guard, every duplicate would flash the lock screen back to station art and refire
  the lookup — and since negative results are deliberately uncached, an unknown track on a
  cue-heavy stream could burn the iTunes API's ~20 req/min budget on a single station.

## 2026-07-09 (station deep links: trust model + launch routing)

- **Deep links route through a MainActor `@Observable` router, not an actor + NotificationCenter
  bridge.** `StationLaunchRouter` (app target, owned by `AppServices`) holds a latest-wins
  `pending: StationLink?`; `onOpenURL` writes it synchronously and `RootView` drains it with
  `.onChange(of:initial:true)` — the `initial` pass covers a link that arrives before the root
  view exists (cold launch), so there is no listener handshake at all. Every producer and
  consumer here is already MainActor, so the earlier actor-based coordinator only added
  suspension points, and with them delivery races (a post landing between listener activation
  and async-sequence subscription was silently dropped; an unserialized deactivate could kill
  delivery for the session; an undeleted pending request replayed on re-appear). The router
  makes those bug classes structurally impossible rather than patched.
- **`PlayStationIntent` stays headless: `AudioPlaybackIntent`, direct `PlaybackController.play`,
  no `openAppWhenRun`.** Reaffirms the 2026-07-03 decision that intents share the controller via
  `AppDependencies.bootstrap()` and never need the view hierarchy. Routing the intent through
  the deep-link surface had forced a foreground launch — which on a locked device demands unlock
  before "Hey Siri, play KEXP" can run, exactly the hands-free scenario the intent exists for.
  Opening the app is inherent to a *URL* launch, so only URL entry points use the router.
- **Deep-link URLs are parsed as untrusted input.** Any installed app or web page can open a
  custom-scheme URL, so `StationLink(url:)` accepts only the `shoutkit` scheme (the
  universal-link-style path fallback is gone until associated domains actually ship, at which
  point it needs a host allow-list), only the canonical query items `url()` emits (the
  id/stream/url alias fan-in was unowned API surface), and only https stream/artwork URLs — a
  crafted link must not point playback at cleartext or local-scheme resources. Residual accepted
  risk, recorded deliberately: a link can still name an arbitrary https stream with arbitrary
  display metadata; opening a link is a user action, and the same risk profile applies to any
  radio app with URL-openable stations. Revisit (resolve-by-id against the directory, or an
  autoplay confirmation) if links ever arrive from less user-mediated surfaces.
- **`StationLink` stays in RadioDirectory despite carrying the app scheme.** Layering-wise it is
  app routing policy and belongs in the app target, but CI's test jobs run package tests only —
  moving it would orphan its round-trip/rejection suite. Accepted tradeoff until an app-hosted
  unit-test target exists.

## 2026-07-06 (Now Playing artwork: ambient acrylic backdrop + Liquid Glass hero)

- **Now Playing's artwork treatment moved into DesignSystem as two composable components**
  instead of view-local styling in `NowPlayingView`: `AmbientArtworkBackdrop` (station artwork
  blurred/saturated under `.ultraThinMaterial` with a legibility scrim — the "acrylic" ambient
  layer, falling back to the brand spotlight gradient when artwork is absent and to a flat
  background under Reduce Transparency) and `HeroArtworkView` (artwork tile on a
  `.glassEffect(.clear)` ledge with a specular rim, spring-scaling with playback state;
  Reduce Motion drops the animation). `HeroArtworkView` composes the existing
  `StationArtworkView` as its tile core, so rows, cards, mini player, and the Live Activity
  are untouched.
- **No `#available(iOS 27)` guard needed**: a scan of the iOS 27 SDK's SwiftUI
  `.swiftinterface` shows no new glass/acrylic API in 27 — the Liquid Glass family
  (`Glass`, `glassEffect`, `GlassEffectContainer`) is unchanged from iOS 26 and available at
  the packages' iOS 26 floor. The "modern" treatment is compositional, not a new API.
- **Directory artwork is treated as a color source, not a bitmap to stretch.** Live
  measurement of Radio Browser's top-clicked stations put the median favicon at ~180px
  (60% ≤192px) with no dimension metadata or icon proxy in the API, and no free high-res
  CDN alternative (Google s2 caps at what sites publish; Clearbit's logo API is sunset). So
  both components consume a shared `ArtworkLoader` (plain `URLSession` + shared `URLCache`,
  replacing `AsyncImage`, which exposes neither pixel size nor the bitmap) that returns the
  decoded image, its pixel size, and a 3×3 box-filtered color grid. The backdrop blur-washes
  artwork ≥512px and otherwise renders the grid as a `MeshGradient` (resolution-independent
  "acrylic", never a smeared solid); the hero caps its tile at ~2.5× the bitmap's native
  points (floor 120pt) so tiny icons read as a crisp badge on the glass plate rather than an
  upscaled blur. Palette samples get a mild saturation boost and brightness clamp so flat
  favicon backgrounds can't wash the mesh out. The loader also elects an `accentColor` —
  the most vibrant sample (saturation weighted toward mid brightness), re-clamped to a band
  where white glyphs stay legible — which `NowPlayingView` applies as a local `.tint` over
  the root brand tint, so transport controls, the Live badge, sleep timer, AirPlay active
  state, and the favorited heart sit in the artwork's color world; monochrome artwork
  yields `nil` and the screen falls back to brand colors.

## 2026-07-06 (iOS 27 adoption strategy + NowPlaying framework)

- **Ship beta 1 on the iOS 26 deployment target; adopt iOS 27 APIs behind `#available`.** WWDC26
  (June 2026) landed while 0.2.0 was in flight. The active toolchain here is already Xcode 27
  beta / iOS 27 SDK, so adoption is a runtime-availability question, not a toolchain migration.
  Raising the minimum to 27 would shrink the beta pool for zero user benefit; staying 26-only
  with guarded 27 paths costs one `if #available` per seam. Revisit the floor when beta metrics
  show the iOS 26 share is negligible. (App Store SDK mandate cadence — iOS 26 SDK required
  since 2026-04-28 — implies the iOS 27 SDK becomes mandatory ~spring 2027; no pressure.)
- **Adopted iOS 27's NowPlaying framework via the existing `NowPlayingPresenting` seam.**
  `MediaSessionNowPlayingCenter` (Playback package) implements the protocol on the new typed
  `MediaSession` API — `RadioContent` is purpose-built for live radio (`stationName` /
  `programName` / `duration: .live`), commands are structured values instead of
  `MPRemoteCommandCenter` global mutation, and artwork is an async provider keyed by URL id
  (system-cached; station switches invalidate naturally, deleting our manual cache
  bookkeeping). Runtime selection lives in `PlaybackController`'s production convenience init:
  iOS 27 → MediaSession, iOS 26 → legacy `NowPlayingCenter`. The seam — added in 0.2.0 purely
  for testability — meant zero changes to the controller, its tests, or the fakes; this is the
  payoff for protocol-first service boundaries. The legacy path stays shippable as a one-line
  fallback while the framework is first-beta. API surface was verified by reading the SDK's
  `.swiftinterface` directly (the framework postdates public documentation coverage).
- **Skipped iOS 27's AI frameworks** (Foundation Models, Core AI, Music Understanding) — no
  credible ShoutKit feature earns their complexity today. Recorded in `docs/releases/0.3.0.md`
  with the rest of the 0.3.0 plan (App Intents entity schemas, quick-play widget, QA items).
- **Concurrency idiom convention: UI packages use default MainActor isolation; infra packages
  stay explicit.** The six UI packages (DesignSystem + five feature packages) now set
  `.defaultIsolation(MainActor.self)` (Swift 6.2's "approachable concurrency" default,
  recommended for UI modules) — unannotated code in them is main-actor by construction, so
  future helpers can't accidentally land nonisolated. `RadioDirectory`/`Playback`/`Persistence`
  deliberately do *not*: isolation there is load-bearing design (actors, protocol seams), and
  explicit annotations are the documentation. One fix surfaced: a `static let` default value
  still evaluates in a nonisolated context under default isolation, so
  `LinearGradient.shoutKitSpotlight` (reads isolated Color tokens) needed explicit `@MainActor`.
  Also adopted `isolated deinit` (Swift 6.4 toolchain) in `NowPlayingCenter` and
  `AVPlayerAudioOutput`, deleting the two `nonisolated(unsafe)` cleanup-state workarounds whose
  only reason to exist was that deinit used to be unavoidably nonisolated.

## 2026-07-05 (icon, first-run, String Catalog)

- **App icon**: a programmatic placeholder, not final design. Generated a 1024×1024 PNG with a
  small Swift/Core Graphics script (radio-wave arcs + center dot over the brand gradient,
  mirroring the in-app "dot.radiowaves.left.and.right" motif) and wired it as a modern
  single-size `AppIcon.appiconset` (`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; Xcode derives
  every smaller size from the one 1024 source — confirmed present in the built app bundle).
  Unblocks TestFlight submission today; swap for a real design before any public/non-beta release
  — this was an explicit scope tradeoff, not a "good enough forever" choice.
- **First-run overlay**: `WelcomeOverlayView` (app target, not a shared package — one-off app-shell
  chrome, same category as `RootView`), gated by `@AppStorage("hasCompletedFirstRun")` and
  presented as a `.fullScreenCover`. One screen, not a carousel, per the release plan. Verified
  both states: fresh install shows it, and setting the flag via `simctl ... defaults write` +
  relaunch confirms it does not reappear.
- **String Catalog adoption** — the mechanically interesting part. Most SwiftUI string literals
  (`Text`, `Button`, `Label`, `.accessibilityLabel`, etc.) take `LocalizedStringKey` and need zero
  code changes to become localizable; they auto-extract into any `.xcstrings` catalog present in
  their module at build time. The only call sites that needed manual `String(localized:bundle:)`
  wraps were genuinely plain-`String` APIs: `RadioDirectoryError.errorDescription` (8 strings) and
  `SectionHeaderView`'s 5 static call sites (its one dynamic, genre-interpolated call — "\(genre)
  Stations" — was deliberately left verbatim; network-sourced text isn't a translation unit, and
  `SectionHeaderView`'s parameter type was deliberately left as plain `String` rather than
  `LocalizedStringKey`, since that dynamic call site couldn't satisfy the latter anyway).
  Added a `Localizable.xcstrings` to every package/target with user-facing strings: the app,
  the widget extension, `DesignSystem`, `RadioDirectory`, and the four feature packages
  (`BrowseFeature`, `PlayerFeature`, `SearchFeature`, `LibraryFeature`) — 8 catalogs total, each
  package declaring `defaultLocalization: "en"` and `resources: [.process("Resources/
  Localizable.xcstrings")]` (SPM requires the former whenever a target has localized resources).
  `Playback`/`Persistence` were skipped — no user-facing strings live there.
  **Empirically falsified an assumption before shipping it**: a plain `xcodebuild build` does
  *not* sync newly-discovered `LocalizedStringKey` literals back into the checked-in `.xcstrings`
  source file — that turned out to be an Xcode-IDE-only behavior, not a CLI one, and no amount of
  rebuilding populated the catalogs. The real CLI-only mechanism, verified by direct inspection
  of the resulting JSON: `xcodebuild -exportLocalizations` (reads the compiler's
  `-emit-localized-strings` stringsdata output across every target/package, 99 trans-units found)
  piped into `xcodebuild -importLocalizations` on that same export — this round-trip genuinely
  writes the discovered keys into each package's source `.xcstrings` (92 keys landed across all
  8 catalogs, confirmed present by reading each file, including the interpolated
  `"The station directory returned HTTP %lld."` case). Since the app currently ships English only
  (`sourceLanguage: "en"`, no other language added), populated vs. empty catalogs have zero
  visible runtime effect today — this exercise is entirely groundwork: a contributor can now open
  any of these catalogs in Xcode, add a language, and start translating with real keys already
  in place, instead of starting from nothing.

## 2026-07-05 (Settings & About)

- Added `SettingsFeature` (GPL, one-package-per-surface convention) presented as a sheet from a
  gear on Listen Now — no fifth tab; four tabs + mini-player is already the full shell.
- `SettingsStore` lives in **Persistence**, not the feature package: the composition root consults
  it (`onStationPlayed` checks `isPlayReportingEnabled` before reporting to Radio-Browser), and
  Persistence is host-testable — the store takes an injected `UserDefaults` and has suite-isolated
  tests. Play reporting defaults **on** (anonymous, Radio-Browser etiquette) with the opt-out the
  README privacy story promised.
- License texts (GPL-3.0/MIT) ship **in the binary** as SettingsFeature bundle resources — copies
  of the repo LICENSE files. Deliberate duplication: license texts are immutable, and in-app
  display beats linking out. External links centralized in `ProjectLinks` — the GitHub URLs point at
  `github.com/cascadiacollections/shoutkit` (the published home); fix there if the repo moves.

## 2026-07-05 (0.2.0 beta kickoff)

- Started the 0.2.0 TestFlight-beta milestone (plan: `docs/releases/0.2.0.md`). Bundle ID is now
  `com.cascadiacollections.shoutkit` (widget: `.Widgets` suffix); `MARKETING_VERSION` 0.2.0;
  `ITSAppUsesNonExemptEncryption = NO` declared in both Info.plists (HTTPS only) so App Store
  Connect never asks the export-compliance question per build.
- Sleep timer chosen as the beta-1 feature headliner (quick-play widget deferred to beta 2).
  `SleepTimer` lives in Playback as a playback-agnostic `@Observable` with an `onFire` hook the
  app wires to `PlaybackController.pause()` at bootstrap — same inversion pattern as
  `onStationPlayed`. It **pauses** rather than stops so the mini-player survives overnight and
  morning resume is one tap. Views derive the countdown from `fireDate` via `TimelineView`
  (`.periodic`, 1s) instead of the model ticking; remaining-time math takes an injected clock for
  tests. The scheduled `Task.sleep` is reliable in the background because the audio background
  mode keeps the process alive whenever the timer matters (something is playing).
- Added `CHANGELOG.md` (Keep a Changelog); release notes for TestFlight should be derived from it.

## 2026-07-05 (Playback host-testability)

- Made the Playback package build and run its tests on the mac host: extracted ICY parsing into a
  platform-agnostic `ICYMetadataParser` (tests previously reached through the iOS-only
  `AVPlayerAudioOutput` to get at pure string logic), gated `AVPlayerAudioOutput` and
  `NowPlayingCenter` behind `#if canImport(UIKit)`, and declared `.macOS(.v15)` in the manifest.
  `PlaybackController` now has a fully-explicit designated initializer (what tests use) plus a
  UIKit-gated production convenience `init(directory:)`, so app call sites are unchanged.
- CI's Playback step was promoted from `build-for-testing` (compile-only) to a real host
  `swift test` — all three package suites now execute on every push; the gated iOS types still
  compile via the app build job.
- Immediate payoff: the first-ever execution of the suite caught a latent parser bug that
  compile-only verification had hidden — `parseTrack` trimmed whitespace *before* searching for
  the `" - "` separator, destroying the leading separator in empty-artist titles like
  `" - Orphan Title"`. The parser now searches the raw string and trims the halves.

## 2026-07-05 (FOSS foundations + monetization groundwork)

- Audited the code and full git history before licensing: sole author throughout (all commits by
  the repo owner, with Claude co-author trailers — outputs belong to the user), no secret ever
  committed (only the `your_key_here` placeholder in the template appears anywhere in history),
  zero remote package dependencies, zero bundled third-party assets (the asset catalog holds only
  `Contents.json`; KEXP artwork loads from KEXP's own public URL at runtime), and no foreign
  copyright headers. Clean single-owner copyright → free to license as chosen.
- **Hybrid licensing with monetization in mind**: GPL-3.0 for the app + feature packages +
  LiveActivity (distributed forks must stay open, deterring clone-and-sell), MIT for the reusable
  infrastructure packages (RadioDirectory, Playback, Persistence, DesignSystem) to maximize
  library adoption. Root `LICENSE` is the verbatim gnu.org GPL-3.0 text; MIT lives in per-package
  `LICENSE` files. `TRADEMARK.md` reserves the ShoutKit name/icon (Firefox/VLC pattern) — the
  strongest practical protection against misleading clones. SPDX headers per file were
  deliberately skipped; the LICENSE files + README table govern.
- **DCO over CLA** (`git commit -s`, documented in CONTRIBUTING.md): keeps contribution
  provenance clean enough to preserve future relicensing/dual-licensing options without
  CLA-signing friction.
- Donation posture: `.github/FUNDING.yml` (GitHub Sponsors) now; an in-app IAP tip jar is the
  review-safe path later — keep it a pure tip (any unlock changes the App Store category and the
  "free if you build it" story).
- CI (`.github/workflows/ci.yml`): host test suites (RadioDirectory, Persistence), app build +
  Playback `build-for-testing` against the simulator with `CODE_SIGNING_ALLOWED=NO`, and
  SwiftLint. Targets the `macos-26` runner image; unverifiable until the repo has a GitHub remote.
- Added `PrivacyInfo.xcprivacy` (no tracking, no collected data, UserDefaults reason CA92.1 for
  the Shortcuts station cache) wired into the app target, and a README privacy section listing
  the complete network surface — the transparency is part of the donation pitch, not just
  compliance.

## 2026-07-04 (architecture review round)

- Abstracted the system now-playing surface behind a `NowPlayingPresenting` protocol
  (`NowPlayingCenter` is the production conformance). `PlaybackController` unit tests previously
  constructed real `NowPlayingCenter`s, registering targets on `MPRemoteCommandCenter.shared()` —
  global system state mutated from unit tests — and the lock-screen contract was unassertable. A
  test spy now covers it: pause-during-loading pushes `isPlaying: false`, stop clears, remote
  commands drive the controller.
- Adopted Swift 6 typed throws across the directory layer: `RadioDirectoryProviding` methods are
  `throws(RadioDirectoryError)`, and Browse/Genre/Search phases carry the typed error instead of
  `.failed(String)`. `RadioDirectoryError.isRetryable` distinguishes try-again failures (network)
  from permanent ones (parse/config); Browse and Listen Now show a Retry button only when retrying
  can plausibly help. Error copy was generalized from "SHOUTcast directory" to "station directory"
  since Radio-Browser is the default source. Note: `async let` erases a child task's typed error to
  `any Error`, so `BrowseViewModel.refresh` needs an explicit `catch let error as
  RadioDirectoryError` clause. `PlaybackState.failed` stays `String` — its failures also come from
  AVPlayer, not just the directory.
- Added `CachingRadioDirectory`, an actor decorator with a 60s TTL and single-flight coalescing for
  `genres()`/`topStations(limit:)` (pass-through otherwise; failures never cached). Listen Now and
  Browse both refresh at launch and previously issued duplicate directory fetches — also a
  Radio-Browser etiquette concern. The clock is injected for TTL tests. Wrapped outermost in
  `AppDependencies.makeDirectory()` so preferred-merged results are what gets cached.
- Headless test execution: `swift test` fails at CodeSign because the build writes provenance
  xattrs onto the .xctest bundle ("resource fork … detritus not allowed"). Workaround that works:
  let the build fail at signing, then `xattr -cr` + `codesign --force --sign -` the bundle and
  `swift test --skip-build`. RadioDirectory (22 tests) and Persistence (4 tests, after declaring
  `.macOS(.v15)` in its manifest for host runs) pass this way. Playback tests compile
  (`build-for-testing`) but use iOS-only APIs (`UIImage`, `AVAudioSession`) — run those via Cmd+U.
  A `ShoutKit.xctestplan` was added and wired into the shared scheme; this Xcode beta's headless
  `xcodebuild test` could not resolve package testables through the project reference, but the
  plan should work from the Xcode GUI.

## 2026-07-03 (Live Activity)

- Added a `ShoutKitWidgets` WidgetKit extension target (hand-authored in `project.pbxproj`
  following the placeholder object-ID convention, IDs `...48`/`...58`–`...59`/`...68`–`...81`)
  hosting a lock screen + Dynamic Island now-playing Live Activity. No App Group: the activity is
  driven entirely from the app process via ActivityKit, and Live Activity views can't load network
  images anyway, so artwork was scoped out deliberately rather than half-shipped.
- The shared contract lives in a new `LiveActivity` package with two products:
  `NowPlayingActivityCore` (attributes only, dependency-free — the only thing the extension links,
  keeping it lean) and `NowPlayingActivityKit` (the app-side `NowPlayingActivityCoordinator`,
  which depends on Playback). Attributes are fixed per activity, so a station switch ends the old
  activity and requests a fresh one.
- `PlaybackController` gained `onStateChange`/`onNowPlayingChange` hooks (same pattern as
  `onStationPlayed`) via `didSet`, so Playback stays ignorant of ActivityKit; the app wires the
  coordinator in `AppDependencies.bootstrap()`.
- ActivityKit's `Activity` handle is thread-safe but not Sendable-annotated, and `update`/`end`
  are async — under strict concurrency the calls need a scoped `nonisolated(unsafe)` binding.
  This is the third framework-boundary concurrency workaround in the codebase (after
  `MPMediaItemArtwork` and `MPRemoteCommandCenter`).
- Live Activity rendering can only be fully verified on a device (simulator verification covered:
  extension embeds correctly, plists are right, app launches with the wiring active).

## 2026-07-03 (keyless discovery + App Intents)

- Adopted Radio-Browser (radio-browser.info) as the **default** discovery source so search, genres,
  and popular stations work with zero API key — it's a free, open-source, self-hostable community
  directory, a better FOSS fit than SHOUTcast's key-gated API. `SHOUTCAST_DEV_KEY` still opts into
  the SHOUTcast directory; `ShoutcastDirectoryClient` was deliberately kept, not deleted.
- `RadioBrowserDirectoryClient` walks the DNS-load-balanced mirror list
  (`all.api.radio-browser.info`, then named mirrors) with backoff between attempts, so one dead
  mirror doesn't take discovery down. API shapes (`url_resolved`, `stationuuid`, comma-separated
  `tags`, `bitrate` 0 = unknown, `hidebroken`/`order`/`limit` params) were verified against the
  live API before writing the Codable layer.
- Radio-Browser etiquette is wired in: descriptive User-Agent, and plays are reported via
  `/json/url/{stationuuid}` through a `StationPlayReporting` hook composed into
  `PlaybackController.onStationPlayed` alongside recents logging. Non-UUID station ids (bundled,
  SHOUTcast) are skipped rather than sending garbage requests.
- Favicons from Radio-Browser are frequently plain `http://`, which ATS blocks for image loads
  (the app's exception covers AV media only) — the mapper upgrades them to `https://` best-effort;
  hosts that don't support TLS fall back to the placeholder artwork.
- Did NOT map Radio-Browser's `clickcount` onto `Station.listenerCount` — clicks-over-time and
  live listeners are different semantics and the row UI renders "N listeners".
- Replaced the `OpenShoutKitIntent`-only stub with a real `PlayStationIntent`: `StationEntity`
  snapshots everything needed to play (mirroring how Persistence snapshots stations), resolved
  from favorites → curated → recents → a UserDefaults cache of previously surfaced search results
  (Shortcuts persists only entity ids, so saved shortcuts must re-resolve from local knowledge),
  with free-text matching hitting the live directory.
- Moved one-time service construction into `AppDependencies.bootstrap()` (idempotent, @MainActor):
  App Intents run in-process but outside the view hierarchy, so they can't reach the SwiftUI
  environment — bootstrap gives the scene and intents the same `PlaybackController` instead of an
  intent ever constructing a second `AVPlayer` that would fight for the audio session.

## 2026-07-03 (review fixes, part 2)

- `StationRow` was still a row-level `.onTapGesture` wrapping a separate inner `Button`, both
  wired to the same `onTap` — a button nested inside a tappable region, which is ambiguous for
  hit-testing and collapsed to one confusing VoiceOver element even after adding an accessibility
  action in part 1. Rebuilt the whole row as a single `Button`; the play/pause glyph is now a
  non-interactive visual indicator with its own Reduce Transparency/Increase Contrast fallback
  (mirroring `GlassControlSurface`, since swapping to a raw `.glassEffect` would otherwise have
  dropped the accessibility fallback the system `.glass` button style provided for free).
- Added `assertEnvironmentInjected` (DesignSystem) and wired it into `RootView.task`: a Debug-only,
  preview-safe tripwire (`XCODE_RUNNING_FOR_PREVIEWS` guarded) that fails loudly if the app root
  ever forgets to inject `PlaybackController`/`LibraryStore`, instead of every feature view
  silently no-op'ing on user taps.

## 2026-07-03 (review fixes)

- Keep `.tabViewBottomAccessory` attached at all times with a "Not Playing" placeholder (Apple
  Music's own pattern): conditionally applying the modifier changes the TabView's structural
  identity and resets every tab's navigation/scroll state whenever playback starts or stops.
- `pause()` during endpoint resolution now cancels the pending start — otherwise audio began
  playing after the user paused. `resume()` from that state re-plays since no player exists yet.
- Added `AVAudioSession` interruption + route-change handling in `AVPlayerAudioOutput` (new
  `AudioStatus.interruptionBegan/.interruptionEnded(shouldResume:)` cases); `PlaybackController`
  auto-resumes only when playback was active and the system hints `.shouldResume`. Headphone
  unplug (`oldDeviceUnavailable`) pauses explicitly.
- Async status hops from AVPlayer KVO are generation-guarded so a late delivery from a previous
  player can't be attributed to a newly started station.
- Station switches tear down the player without deactivating the audio session; only a true
  `stop()` releases audio focus (deactivating mid-switch let other apps' audio blip in).
- Removed the Playback→Persistence dependency: `PlaybackController` exposes `onStationPlayed`
  and the app layer wires it to `LibraryStore.logRecent`, keeping playback ignorant of storage.
- `NowPlayingCenter` now removes its `MPRemoteCommandCenter` targets on deinit, returns
  `.noActionableNowPlayingItem` when idle (via an `OSAllocatedUnfairLock` flag readable from
  MediaRemote's queue), and drops cached artwork on station change so the previous station's art
  never shows on the lock screen.
- HIG fixes: 44pt minimum touch targets on the mini-player controls, `minHeight` instead of a
  fixed height on the spotlight card (Dynamic Type), VoiceOver custom action for the favorite
  toggle on `StationRow` (context menus are invisible to combined accessibility elements), and
  search shows its spinner only after the debounce fires.

## 2026-07-03

- Redesigned the app around the Apple Music interaction model for the MVP: a persistent Liquid Glass
  mini-player docked via `.tabViewBottomAccessory` that expands to a full-screen `NowPlayingView`.
  Tabs are now Listen Now · Browse · Search (`.search` role) · Favorites.
- Promoted playback out of `BrowseViewModel` into an app-wide `@MainActor @Observable`
  `PlaybackController`, injected through the SwiftUI environment (`\.playbackController`) so the
  mini-player, Now Playing, and every station row read and drive the same state. Feature view models
  are now discovery-only.
- Placed `PlaybackController` in the `Playback` package (not a feature package) to keep the dependency
  graph acyclic: `DesignSystem` depends on `Playback` for the shared `StationPlaybackPhase`, and
  `Playback` never imports UI. Reusable station UI (`StationRow`/`StationCard`/`StationArtworkView`/
  `SectionHeaderView`/`PlayingIndicator`) lives in `DesignSystem` as pure presentational views.
- Abstracted audio behind an `AudioOutput` protocol (`AVPlayerAudioOutput` for production, a fake in
  tests) so `PlaybackController` state transitions are unit-testable without real media. Added ICY
  timed-metadata parsing, `timeControlStatus`-driven buffering/playing states, `MPNowPlayingInfoCenter`
  + `MPRemoteCommandCenter` lock-screen integration, and audio-session teardown on stop.
- Wired the scaffolded SwiftData layer: `ShoutKitModelContainer` factory + `@Observable` `LibraryStore`
  (favorites with instant `favoriteIDs`, de-duped recents capped at 25). Added `streamURLString` and
  `artworkURLString` to the models so favorited/recent stations remain playable and render artwork
  without a directory round-trip. Container + store injected at the app root.
- Added the mini-player accessory only when a station is active (conditional modifier, not just empty
  content) so no empty glass pill is drawn at idle, matching Apple Music.
- Kept the bundled/preferred/ShoutcastDirectoryClient seams unchanged; discovery is designed around the
  keyless bundled path and lights up automatically when `SHOUTCAST_DEV_KEY` is present.

## 2026-07-12

- Evaluated CarPlay as **architecturally viable but not this milestone's implementation work**.
  The hard part is already centralized: `PlaybackController` is the single app-wide playback owner,
  remote transport actions flow through the `NowPlayingPresenting` seam, and station snapshots
  (`Station`, favorites/recents persistence rows, and `StationEntity`) already carry the name,
  genre, artwork URL, and stream URL a minimal CarPlay browse list needs. That means a first pass
  can stay thin — a `CPTemplateApplicationSceneDelegate`, one station-list template sourced from
  favorites/recents/curated stations, row selection calling `PlaybackController.play(_:)`, and the
  system `CPNowPlayingTemplate` for transport controls — with no separate playback stack and no
  `MPPlayableContentManager` content tree.
- Deferred actual implementation anyway because the blockers are platform rollout risk, not model
  gaps. The checked-in app entitlements still do not include CarPlay audio, the app has no CarPlay
  scene manifest yet, and `PlaybackController`'s production initializer still pins iOS 27 to the
  legacy `NowPlayingCenter` while `MediaSession` parity is verified. Shipping a brand-new CarPlay
  surface in the same window as the now-playing runtime prove-out would stack two moving platform
  pieces at once, so the roadmap keeps CarPlay as a backlog item until the entitlement lands and
  the `MediaSession` path becomes the production default.

## 2026-06-24

- Created a real Xcode workspace plus local Swift packages instead of a single Swift package, because the MVP needs an iOS app target, assets, capabilities, and future extension targets.
- Kept milestone 1 focused on the app shell and module boundaries. The directory client, playback behavior, SwiftData store wiring, widgets, intents, and ActivityKit integrations are represented by clean package seams and will be implemented in later milestones.
- Used optional `#include?` for `Secrets.xcconfig` so the app can build in a fresh checkout while still keeping the SHOUTcast developer key outside source control.
- Added Reduce Transparency and Increase Contrast handling to the first reusable glass surface so custom glass starts from an accessible fallback rather than being retrofitted later.
- Kept `PreviewRadioDirectory` for previews, tests, and keyless development, but wired the app to use `ShoutcastDirectoryClient` automatically when `SHOUTCAST_DEV_KEY` is present.
- Declared macOS 13 support only for the pure Foundation `RadioDirectory` package so Swift Testing can run locally; the app product remains iOS 26-only.
- Added a minimal `OpenShoutKitIntent` shortcut scaffold during milestone 1 to establish the App Intents integration point and keep Xcode metadata extraction meaningful.
- Added `PreferredRadioDirectory` so user-loved stations can be guaranteed independently of SHOUTcast directory coverage. KEXP is seeded from its official AAC stream URLs and appears before directory Top stations.
- Replaced the no-key runtime fallback with `BundledRadioDirectory` so live direct streams like KEXP remain available without mixing in fake preview stations. SHOUTcast directory features remain gated by `SHOUTCAST_DEV_KEY`.
- Wired Browse station rows directly to `PlaybackControlling` for the MVP so preferred direct streams can play before the full Now Playing surface exists.

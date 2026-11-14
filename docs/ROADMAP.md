# Holmdel roadmap

A sprint-aligned view of where Holmdel is headed, spanning both **feature** work and
**general engineering** (test infra, CI, tech debt). Sprints are 2 weeks. This complements,
rather than replaces, the per-release plans in `docs/releases/*.md` — those stay the
detailed, checkbox-level source of truth for a release in flight; this document is the
zoomed-out sequencing across releases, revisited every sprint as scope shifts.

**Status snapshot (2026-11-01).** Everything below is a proposal, not a commitment.

The 2026-08-13 snapshot said nothing had ever been released and the repo had zero git tags.
That is no longer true. `v0.4.0` was tagged in #187 (2026-08-30); `release.yml` ran, and the
GitHub Release is still a **draft**, which is what `docs/RELEASING.md` calls a cut until
someone publishes it. 0.1.0, 0.2.0, and 0.3.0 were never tagged. `v0.4.0` is still the first
real release. The tree's `MARKETING_VERSION` has since moved, all twelve sites together, to
`0.5.1` (#198, #202) with no `v0.5.x` tag, and a public TestFlight beta of 0.5.1 (31) is
recorded in `docs/TESTFLIGHT.md`. CarPlay remains unreachable until Apple grants the
entitlement (see the backlog).

This document was re-baselined on 2026-08-07 after drifting about a release behind the
tree. It had CarPlay deferred (it shipped), it listed two CI gaps that `ci.yml` had already
closed, and it predated the watchOS app, the equalizer, on-disk station caching, the power
review, and the UX consolidation pass. `DECISIONS.md` stayed current throughout and is the
better record of what happened; this file is only useful if it says what is *next*, so the
practice that matters is the last bullet of "How to use this doc."

## Shipped since the last re-baseline

Recorded here once so the next reader doesn't have to reconstruct it from `git log`. Detail
for each is in `DECISIONS.md` under its date. This list is the 2026-08 re-baseline
inventory, not a log of everything since; later shipments are in `CHANGELOG.md` and
`DECISIONS.md`.

- **CarPlay** — `CPListTemplate` (favorites + recents) over `CPNowPlayingTemplate`, on the
  existing `PlaybackController`. **The code shipped; the feature did not.** Declaring
  `com.apple.developer.carplay-audio` was mistaken for holding it — it is granted per-team by
  Apple on request, this team was never granted it, and the declaration broke automatic signing
  on the first TestFlight archive. The entitlement is removed and CarPlay is unreachable until
  the request is filed and approved. See `DECISIONS.md`, 2026-09-06.
- **watchOS companion** — native now-playing and recents, plus a "Play Last" complication,
  with its own minimal service graph and `AVPlayer`-backed engine.
- **Equalizer** — preset curves ported from the Android client's band math, attached to
  AudioStreaming's `AVAudioEngine` node graph.
- **Stations on disk** — a JSON snapshot painted at launch, so a cold start shows stations
  instead of a spinner, with a six-hour stability window.
- **Power review** — speculative artwork prefetch and launch prewarming now stop under Low
  Power Mode, Low Data Mode, and on cellular.
- **UX consolidation** — four tabs to three, genre chips that browse a genre rather than
  search for its name, and a transport row where each control means one thing.
- **Playback hardening** — OS interruptions and audio-session loss, bounded reconnect with a
  capped backoff, mirror rotation in the directory transport, and the Bluetooth/AVRCP
  artwork fix.
- **CI** — the Playback suite and the app test plan both run (this doc claimed they didn't),
  and the SwiftPM store is cached.

## Now — engineering hardening

The sprint this document scheduled twice and skipped twice. The batch in flight on
2026-08-13 landed in #138; items that merged later cite their own PRs. The exit criteria
at the end of this list are met.

- [x] **Code coverage collected and published.** Nothing measured coverage anywhere: the
      test plan had `codeCoverage` off and the host `swift test` runs passed no flag.
      Baseline only — no threshold, no gate, no third-party uploader. A gate on a tree that
      has never measured buys tests for whatever is cheapest to cover.
- [x] **The watchOS target compiles in CI.** It is a separate top-level target with no
      shared scheme, so ~670 lines could break with every check green. (The *widget*
      extension was already covered — `Holmdel` depends on and embeds it.)
- [x] **`Packages/PlaybackEngineAudioStreaming`** — the codec dependency leaves the
      MIT-licensed `Playback` package (#122), with a CI step asserting it stays gone.
      Closes #123 and #126 with it.
- [x] **`PlayerFeatureCore`** — the artwork selection rule is host-testable and tested.
- [x] **Accessibility, first real pass** — the sleep timer announces its remaining time
      (it previously announced only that it was running), the transport button scales with
      Dynamic Type, and station/track read as one VoiceOver element on both player surfaces.
- [x] **Make SwiftFormat blocking** (#142). Done in #207 (2026-09-12). The one-time
      reformat is recorded in `.git-blame-ignore-revs`, and `ci.yml` runs
      `swiftformat HolmdelApp Packages --lint` with no `continue-on-error`.
- [x] **The watch app does not ship with the phone app. Fix the embed** (#141). Fixed in
      #166 (merged 2026-08-13). The root cause was a missing `WKCompanionAppBundleIdentifier`
      — the target was configured as a *standalone* watch app — plus the absent copy phase.
      A real build emits `Holmdel.app/Watch/HolmdelWatchApp.app` (watchOS Mach-O, complication
      nested inside), and CI fails the build if that payload is missing. **Still unverified:
      that it installs and pairs**, which needs a paired simulator or hardware — see
      `DECISIONS.md`.
- [x] **Audit the `try?` sites** (#143), done in #153. Re-checked the gate first: on the
      current `xcode-27` toolchain, a probe with `Task { try await … }` still emits no
      unhandled-error diagnostic, so there is nothing to enable yet. Keep this
      probe command (against a file that contains an unhandled `Task { try await … }`)
      handy to detect when it lands:
      `swiftc -typecheck -warnings-as-errors /tmp/task-unhandled-error-probe.swift`.
      The audited call sites left as `try?` are now explicitly marked best-effort
      where the intent was ambiguous.
- [x] Extracted `LibraryFeatureCore` and `SettingsFeatureCore` (#144) in #203, as
      `PlayerFeatureCore` did for the player. Both now run host-test suites in CI. The
      2026-08-13 snapshot had this checked off before the extraction had merged.
- [x] `StationCard` scales with Dynamic Type (#145), done in #158. Fixed-width tiles use a
      `@ScaledMetric` (base 150 pt), capped so an accessibility size does not grow past the
      shelf.

**Exit criteria (met):** coverage is published for every package; the watch target's build
is a required check; the format check blocks (#207); the watch app is embedded and CI fails
the build if the payload is missing (#166). Pairing on a watch is still unverified — that
note stays on the embed item above.

## Next — 0.4.0 feature round

**"None of it has started" was wrong when written and is corrected here** — search filters
shipped in #157 and issue #151 is closed. Favorites export/import, still open at the
2026-08-13 snapshot, shipped in #156 and #150 is closed. Ambient playback (#4) is the one
item in this section that is still open. Listing completed work as pending is why the last
bullet of "How to use this doc" exists.

- [ ] **Ambient playback on ad detection** (#4). Reuse the existing ICY ad-break markers
      (`Spot Block Start/End`, already suppressed from displayed titles) as the trigger.
      Ship a bundled loop first — on-device ML nature-sound generation is a stretch goal,
      not a v1 requirement. Off by default behind a Settings toggle until it is proven not
      to false-trigger on non-Triton/iHeart stations.
- [x] Favorites export/import (#150) — plain JSON, no account, no server. Shipped in #156
      as Settings → Favorites Backup (`fileExporter` / `fileImporter`, merge by station id).
      Recents and recently heard tracks are not included.
- [x] Search filters (#151) — bitrate, tag/genre, country, over Radio-Browser's existing query
      params. **Shipped in #157**; `StationSearchFilters.swift`,
      `RadioBrowserDirectoryClient+Filters.swift`, and three test files are in the tree.

**Exit criteria:** the ad-break feature doesn't false-trigger across the top 20 Radio-Browser
stations by listener count; crash-free ≥ 99.5%; no open P0/P1 for a week.

## Then — decide about the dark features

Five features were built, wired, and tested, and sat at `internalOnly` /
`defaultEnabled: false` in `FeatureCatalog` — no user outside a Debug build ever saw them.
**Two are now resolved** (`recommendations` deleted, `diagnostics` decided; both 2026-08-13),
leaving three.

That is not a backlog, it is unshipped inventory, and it costs something to carry: every one
of them is code that has to keep compiling, keep passing tests, and keep being reasoned
about during refactors. Each needs a decision — **promote or delete** (#146).

The inventory was measured on 2026-08-13 and is ~2,050 lines, distributed far more unevenly
than this section implied — `diagnostics` alone is more than the other four combined.

**A line count next to a flag is not a deletion estimate**, and treating it as one was the
mistake this section originally made and then repeated: three of the five share code with
shipping features, so the flag's blast radius is smaller than the feature's footprint. Each
entry below states what is actually dark.

- [x] `recommendations` (320 lines) — **deleted 2026-08-13.** The only one of the five that
      could be removed without touching a shipping feature. `BrowseFeature` lost its
      `FeatureFlags` dependency with it, and `RecommendationHashing` went too. See
      `DECISIONS.md`. Deleted in #168.
- [ ] `prewarmStations` — launch-time DNS/TLS warming of top stations. **Not cleanly
      deletable either**, and the 304-line figure first written here was wrong: the flag
      gates far less than the machinery. `StationConnectionPrewarmer` (133 lines) is called
      by `WarmupRadioAudioQueueIntent` (`HolmdelAudioIntents.swift:82`), a **shipping App
      Intent with no flag gate**, and `LibraryStore+Prewarm.swift` (123 lines) is mostly not
      prewarm at all — `rankedStations(limit:)` drives CarPlay
      (`HolmdelCarPlaySceneDelegate.swift:106`), alongside `favoriteStations()`,
      `mostRecentStation()`, and `refreshStreamURLSnapshot()`. The genuinely dark surface is
      the flag, the launch-warmup block in `AppDependencies+Warmups.swift:26`,
      `prewarmStreamURLs(limit:)`, and the `tapToAudioPrewarmEnabledProvider` wiring (which
      only labels a log line in `TapToAudioLatencyTrace`). Scope it that way, and note that
      deleting the flag leaves the prewarmer itself in place and still used.
- [ ] `geoStations` (173 dark lines) — region-filtered discovery. **Not cleanly deletable**,
      contrary to the framing above: region identity is threaded into the *shipping* caching
      layer (`CachingRadioDirectory.swift:195`, `DirectoryDiscoverySnapshot.swift:40`) and
      runs for every user today. Only `GeoStationLocationCoordinator` and the flag are dark,
      so scope this as "delete the opt-in precise-location path," not "delete geo".
- [x] `liveActivity` — **deleted 2026-11-14.** It added little over the system Now Playing
      surface and had never reached a user. The ActivityKit view, attributes, coordinator
      and artwork store went; the `LiveActivity` package stays, because the
      **shipped** Quick Play widget lives in it. See `DECISIONS.md`.
- [x] `diagnostics` (1,087 lines — 54% of the inventory) — **decided 2026-08-13: stays
      internal-only, permanently.** It is a developer instrument with no user-facing surface,
      double-gated and with no network egress at all. See `DECISIONS.md` (recorded in #167).
      That entry also flags `DiagnosticsMetricSummary` (422 lines) as a deletion candidate
      *within* the retained feature — nothing reads its summaries programmatically.

## Now — release readiness

Everything gating a public listing that isn't distribution mechanics. **Moved from "Later" to
"Now" on 2026-08-13**, when the argument was that a feature round added to software nobody
could install was the wrong next move. A public TestFlight beta has since gone out by hand
(`docs/TESTFLIGHT.md`, 0.5.1 (31), 2026-10-25). The unchecked items below are still open.
`release.yml` still does not sign or upload.

- [x] Release-process doc — `docs/RELEASING.md`, written 2026-08-13 (#169) and extended
      since. A cut is a draft GitHub Release from a CHANGELOG section. GitHub Actions still
      does not sign or upload. TestFlight uploads are the Xcode Cloud workflow on `main`
      (#229); a push that does not change the app does not upload.
- [x] Version numbering reconciled (#169). On 2026-08-13 the phone app read `0.2.0` while
      the watch and tvOS targets read `0.3.0`, which fails App Store validation for an
      embedded watch app. All twelve `MARKETING_VERSION` sites were set to `0.4.0` together.
      They have since moved together to `0.5.1` (#198, #202). They still match each other.
- [ ] **Publish `v0.4.0`.** The tag and the changelog cut-over landed in #187 (2026-08-30).
      The GitHub Release is still a draft. The notes are current through the commits after
      that tag, and the publish checklist is in `docs/RELEASING.md`. The tag points at the
      2026-08-30 cut, not at `main`. Publishing is Kevin's step.
- [ ] Build-number (`CURRENT_PROJECT_VERSION`) handling. It is shared at the project level
      (both configurations read `2`) and is still incremented by hand. TestFlight already
      has 0.5.1 (31), so the next upload of that version must be higher than 31. #195, #198,
      and #206 were manual edits, not automation. No issue is filed for this.
- [ ] A CI check that the pushed tag matches `MARKETING_VERSION`. Nothing currently catches
      a tag that disagrees with the tree. The live skew is the project reading `0.5.1` while
      the only tag is `v0.4.0`. No issue is filed for this.
- [x] iPhone app icon — Icon Composer `Squan-AppIcon` replaced the programmatic placeholder
      on 2026-09-07. Watch and tvOS icons were not part of that swap; see `docs/RELEASING.md`.
- [ ] Community translations beyond English. String Catalog infra shipped in 0.2.0; the
      catalogs are still English only. No issue is filed for this.
- [ ] The checked-in codesign script (`xattr -cr` + ad-hoc `codesign` + `swift test
      --skip-build`) so the headless-test workaround is one command instead of the commands
      in `CONTRIBUTING.md`. Still open — `.github/scripts/` has other helpers, and none of
      them is this one. No issue is filed for this.
- [ ] Cold-launch and memory baselines captured per build (#148), as an ongoing regression
      check. Still open. #200 recorded a one-time simulator memgraph in `DECISIONS.md`
      (2026-09-07); that is not the per-build CI baseline this issue asks for.
- [ ] `GIT_COMMIT_SHA` stamping verified against a real tagged build (the mechanism shipped
      in 0.2.0). `release.yml` still only extracts changelog notes, so the `v0.4.0` tag did
      not exercise it. No issue is filed for this.

## Next — get off the billed macOS runner

CI spend is currently the largest line item in running this project, and all of it comes
from one label. Holmdel is public, so GitHub's *standard* hosted runners are free;
`xcode-27` is a **larger runner**, and larger runners are billed on public repos like any
other. The 2026-08-11 pass rationed minutes on that label (see `DECISIONS.md`) and bought
roughly a 70% cut, but rationing is not the fix — getting off the label is. Two routes, and
they are not exclusive:

- [ ] **Wait for the free image.** The cheapest possible outcome: when the free `macos-26`
      image ships an Xcode that satisfies `swift-tools-version 6.4` and the iOS 27 SDK,
      swapping `runs-on` takes the bill to approximately zero and every rationing measure
      below can be reverted. `.github/workflows/runner-image-watch.yml` checks weekly and
      files an issue when it lands — the point of automating it is that this is otherwise
      exactly the kind of fact that goes unnoticed for months while the meter runs. As of
      this snapshot it has not: `ci.yml` and `codeql.yml` still run on `xcode-27`, and the
      `macos-26` image readme lists Xcode 26.6 as the newest installed.
- [ ] **Self-hosted runner on the Mac mini.** Still open — no workflow uses a self-hosted
      runner. This route fixes the cost permanently and is *faster* than hosted, for a
      reason that has nothing to do with the hardware: a persistent `DerivedData` makes
      the app build incremental. The 14-minute cold `build` job is
      dominated by compiling unchanged code, and the honest estimate for a warm incremental
      run is low single-digit minutes. Order the work as:
      1. One runner, registered to this repo, **`main`-push jobs only**. That is the
         highest-value and lowest-risk slice: no untrusted code, and it covers
         `release-checks` plus the Swift CodeQL analysis, which is the single most expensive
         job in the repo (~30 minutes per run).
      2. Then PR jobs, **same-repo branches only** — gate on
         `github.event.pull_request.head.repo.full_name == github.repository` and leave fork
         PRs on hosted runners.
      3. Fork PRs stay hosted, permanently, unless step 4 happens.
      4. Only if fork PRs must move: ephemeral VM-per-job (Tart/Lume or similar) with
         `--ephemeral`, never a bare runner on the host.

      The step-2 gate is not optional caution. GitHub's own guidance is that self-hosted
      runners should not be used with public repositories, because a fork PR runs arbitrary
      code on your machine and a non-ephemeral runner keeps state between jobs — that is a
      home-network machine executing anything a stranger opens a PR with. Everything else
      here is operational and manageable: keep the mini awake (`caffeinate`, sleep
      disabled), install the runner as a launchd service so it survives reboot, budget disk
      for multiple Xcode betas, and label it so a workflow can ask for the toolchain it
      needs rather than "some Mac". Worth pricing the electricity and the mini's downtime
      against the hosted bill before committing — at current spend the payback is fast, but
      it stops being fast if the runner needs babysitting.

## Backlog (unscheduled, revisit each sprint)

- **File the CarPlay entitlement request with Apple.** Not a commit — a form
  (developer.apple.com/contact/carplay), reviewed by Apple, measured in weeks. The
  scene configuration and `HolmdelCarPlaySceneDelegate` are already in the tree. A grant
  does not turn CarPlay back on by re-adding one key: the 2026-09-06 removal also dropped
  `UISupportsCarPlay` and `UISupportedInterfaceOrientations~carplay` from `Info.plist`, and
  `com.apple.developer.carplay-audio` is absent from `Holmdel.entitlements`. Restoring is
  that small diff. Until then the code is dead weight in the binary. See `DECISIONS.md`,
  2026-09-06.
- Self-hosted static libogg/libvorbis xcframeworks. The evaluation issue (#124) is closed
  by #154: parked (see `DECISIONS.md`, 2026-08-07). AudioStreaming still resolves the sbooth
  packages at `exact: "0.1.2"` (unchanged at the 1.4.5 pin), so this needs a fork or SwiftPM
  substitution scoped first, and the rest is moot until that is answered. Revisit if app
  size or the provenance concession actually bites.
- On-device ambient-noise generation for the ad-detection feature, only after the
  bundled-loop v1 proves the feature earns its complexity.
- Home Screen widget variants beyond quick-play (recents, currently playing).
- Genre auto-tagging for unlabeled stations.
- On-device AVRCP verification of the 2026-08-06 Bluetooth artwork fix (#147). Diagnosed from
  the code and the AVRCP contract, never tested in a car. Needs hardware, not a commit.
- Resizable-iPhone-app contexts — iPhone Mirroring and iPhone-app-on-iPad (#149), the other
  item that moved out of 0.3.0. Needs hardware too.

## How to use this doc

- Re-baseline at the start of every sprint against actual feedback — this is a proposal,
  not a schedule anyone external depends on.
- **Every open item here carries its issue number.** Keep it that way: an item that exists
  only in this file is one nobody can be assigned, and one whose completion nothing records —
  which is how CarPlay stayed in the backlog for two sprints after it shipped. If a new item
  is concrete enough to work on, file it and put the number here; if it isn't, it belongs in
  the backlog section rather than as a checkbox.
- When a sprint graduates from "next" to "now," give it a `docs/releases/X.Y.md` with the
  same checkbox/exit-criteria structure, and trim this doc to a pointer at it.
- **Anything that slips a sprint without movement should be interrogated, not silently
  rolled forward** — either it's blocked (say why, and say what would unblock it) or it
  isn't actually a priority (cut it). This rule already existed and was not followed: the
  CarPlay entry rolled forward for two sprints after CarPlay shipped, and the `try?` audit
  rolled forward twice behind a gate nobody re-checked. A checkbox that moves between
  sprints untouched is the signal, not the noise.

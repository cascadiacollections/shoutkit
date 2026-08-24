# Holmdel roadmap

A sprint-aligned view of where Holmdel is headed, spanning both **feature** work and
**general engineering** (test infra, CI, tech debt). Sprints are 2 weeks. This complements,
rather than replaces, the per-release plans in `docs/releases/*.md` — those stay the
detailed, checkbox-level source of truth for a release in flight; this document is the
zoomed-out sequencing across releases, revisited every sprint as scope shifts.

**Status snapshot (2026-08-13).** Everything below is a proposal, not a commitment.

**The thing this document did not say, and should have: nothing has ever been released.**
0.1.0, 0.2.0, and 0.3.0 all have changelog sections and release plans, and the repo had
**zero git tags** — `release.yml` is tag-triggered and had never run once. CarPlay, the
watchOS companion, tvOS, widgets, the equalizer, offline caching, iPadOS layouts, and the
accessibility pass have all been built and none of them has reached a user. A roadmap that
sequences the next feature round while the distribution path is untested is measuring the
wrong thing. `v0.4.0` is the first real release; see `docs/RELEASING.md`.

This document was re-baselined on 2026-08-07 after drifting about a release behind the
tree. It had CarPlay deferred (it shipped), it listed two CI gaps that `ci.yml` had already
closed, and it predated the watchOS app, the equalizer, on-disk station caching, the power
review, and the UX consolidation pass. `DECISIONS.md` stayed current throughout and is the
better record of what happened; this file is only useful if it says what is *next*, so the
practice that matters is the last bullet of "How to use this doc."

## Shipped since the last re-baseline

Recorded here once so the next reader doesn't have to reconstruct it from `git log`. Detail
for each is in `DECISIONS.md` under its date.

- **CarPlay** — `CPListTemplate` (favorites + recents) over `CPNowPlayingTemplate`, on the
  existing `PlaybackController`, with the `com.apple.developer.carplay-audio` entitlement
  declared. This was "backlog, blocked on the entitlement" here for two sprints after it
  had already shipped.
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

The sprint this document scheduled twice and skipped twice. Landing in PR #138.

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
- [ ] **Make SwiftFormat blocking** (#142). The mechanism landed — a `workflow_dispatch` Reformat
      job plus `.git-blame-ignore-revs` — but the one-time run has not been done. Dispatch
      it, review the diff, drop `continue-on-error` from `ci.yml`, record the SHA.
- [x] **The watch app does not ship with the phone app. Fix the embed** (#141). Fixed
      2026-08-12. The root cause was a missing `WKCompanionAppBundleIdentifier` — the target
      was configured as a *standalone* watch app — plus the absent copy phase. A real build
      now emits `Holmdel.app/Watch/HolmdelWatchApp.app` (watchOS Mach-O, complication
      nested inside), and the CI warning below is a hard check. **Still unverified: that it
      installs and pairs**, which needs a paired simulator or hardware — see `DECISIONS.md`.
      Original entry follows. This started as a
      suspicion from reading `project.pbxproj` — no `Embed Watch Content` phase, and
      `HolmdelWatchApp` absent from `Holmdel`'s dependencies — and the CI step added to
      check it has now confirmed it against a real build: `Holmdel.app` has no `Watch/`
      payload. So the watchOS companion that `README.md` advertises, and that
      `DECISIONS.md` recorded on 2026-07-16, has never installed alongside the app.
      **This is a P1, not a chore**, and it needs someone with Xcode: adding an embed phase
      by hand-editing the pbxproj is how you get a target that builds green and produces a
      bundle the App Store rejects. Once it is embedded, turn the CI warning into a hard
      failure so it can't regress.
- [x] **Audit the `try?` sites** (#143). Re-checked the gate first: on the current
      `xcode-27` toolchain, a probe with `Task { try await … }` still emits no
      unhandled-error diagnostic, so there is nothing to enable yet. Keep this
      probe command (against a file that contains an unhandled `Task { try await … }`)
      handy to detect when it lands:
      `swiftc -typecheck -warnings-as-errors /tmp/task-unhandled-error-probe.swift`.
      The audited call sites left as `try?` are now explicitly marked best-effort
      where the intent was ambiguous.
- [ ] Extract cores for `LibraryFeature` and `SettingsFeature` (#144), as `PlayerFeatureCore` did
      for the player. Both still have zero tests.
- [ ] `StationCard` is a fixed 150 pt wide while its labels scale with Dynamic Type (#145). Fixing
      it moves every adaptive grid that lays cards out, so it needs a simulator, not a diff.

**Exit criteria:** coverage published for every package; the watch target's build is a
required check; the format check blocks; the watch-embed question answered either way.

## Next — 0.4.0 feature round

**"None of it has started" was wrong when written and is corrected here** — search filters
shipped in #157 and issue #151 is closed. That is the third time this document has listed
completed work as pending (CarPlay for two sprints, then the `try?` audit, now this), which
is why the last bullet of "How to use this doc" exists.

- [ ] **Ambient playback on ad detection** (#4). Reuse the existing ICY ad-break markers
      (`Spot Block Start/End`, already suppressed from displayed titles) as the trigger.
      Ship a bundled loop first — on-device ML nature-sound generation is a stretch goal,
      not a v1 requirement. Off by default behind a Settings toggle until it is proven not
      to false-trigger on non-Triton/iHeart stations.
- [ ] Favorites export/import (#150) — plain JSON via the Share sheet. No account, no server.
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
      `DECISIONS.md`.
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
- [ ] `liveActivity` — off with a stated reason (artwork can lag the track); the reason is
      fixable or it is a decision to delete. Smaller blast radius than it looks:
      `NowPlayingActivityCore` is linked by the **shipped** quick-play widget
      (`QuickPlayWidget.swift:34`), so the package stays either way.
- [x] `diagnostics` (1,087 lines — 54% of the inventory) — **decided 2026-08-13: stays
      internal-only, permanently.** It is a developer instrument with no user-facing surface,
      double-gated and with no network egress at all. See `DECISIONS.md`. That entry also
      flags `DiagnosticsMetricSummary` (422 lines) as a deletion candidate *within* the
      retained feature — nothing reads its summaries programmatically.

## Now — release readiness

Everything gating a public listing that isn't distribution mechanics. **Moved from "Later" to
"Now" on 2026-08-13**, on the argument that a feature round added to software nobody can
install is the wrong next move: this section is what converts the work already done into
something a user receives.

- [x] Release-process doc — `docs/RELEASING.md`, written 2026-08-13. Documents what a release
      currently *is* (a draft GitHub Release from a CHANGELOG section — no signing, no
      TestFlight, no App Store upload, because no Apple secrets are configured) and what is
      still missing.
- [x] Version numbering reconciled. Four sources disagreed: `CHANGELOG.md` had no `[0.3.0]`
      section at all, `docs/releases/0.3.0.md` said 0.3.0 shipped, this file agreed, and the
      project read `MARKETING_VERSION = 0.2.0`. Worse, the *targets* disagreed with each
      other — phone app at `0.2.0`, watch and tvOS at `0.3.0`, which fails App Store
      validation for an embedded watch app. All twelve sites now read `0.4.0`.
- [ ] **Cut `v0.4.0`.** The changelog cut-over and the tag, per `docs/RELEASING.md`. Blocked
      only on the in-flight PRs that still write to `[Unreleased]`.
- [ ] Build-number (`CURRENT_PROJECT_VERSION`) handling. It is `1` everywhere and has never
      been incremented; TestFlight rejects a duplicate build number for a given version, so
      this bites on the *second* upload of a version, not the first.
- [ ] A CI check that the pushed tag matches `MARKETING_VERSION`. Nothing currently catches
      `v0.5.0` tagged against a tree reading `0.4.0`, and this repo's habit is to assert the
      things it believes (Pulse symbols, the watch payload) rather than trust them.
- [ ] Professional app icon — 0.2.0 shipped a programmatic Core Graphics placeholder,
      flagged in `DECISIONS.md` as swap-before-public-release.
- [ ] Community translations beyond English. String Catalog infra shipped in 0.2.0; this is
      populating it.
- [ ] The checked-in codesign script (`xattr -cr` + ad-hoc `codesign` + `swift test
      --skip-build`) so the headless-test workaround is one command instead of tribal
      knowledge in `CONTRIBUTING.md`. Still genuinely open — there is no `*.sh` in the repo.
- [ ] Cold-launch and memory baselines captured per build (#148), as an ongoing regression check.
- [ ] `GIT_COMMIT_SHA` stamping verified against a real tagged build (the mechanism shipped in
      0.2.0; it has never been exercised by an actual release).

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
      exactly the kind of fact that goes unnoticed for months while the meter runs.
- [ ] **Self-hosted runner on the Mac mini.** Fixes the cost permanently and is *faster*
      than hosted, for a reason that has nothing to do with the hardware: a persistent
      `DerivedData` makes the app build incremental. The 14-minute cold `build` job is
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

- Self-hosted static libogg/libvorbis xcframeworks (#124). Parked on its own
  recommendation: AudioStreaming hardcodes `exact: "0.1.2"` on the sbooth packages, so this
  needs a fork or SwiftPM substitution scoped first, and the rest is moot until that is
  answered. Revisit if app size or the provenance concession actually bites.
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

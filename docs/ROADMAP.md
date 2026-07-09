# ShoutKit roadmap

A sprint-aligned view of where ShoutKit is headed, spanning both **feature** work and
**general engineering** (test infra, CI, tech debt). Sprints are 2 weeks. This complements,
rather than replaces, the per-release plans in `docs/releases/*.md` — those stay the
detailed, checkbox-level source of truth for a release in flight; this document is the
zoomed-out sequencing across releases, revisited every sprint as scope shifts.

Status snapshot at time of writing: 0.2.0 (first TestFlight beta) is in progress; 0.3.0
(`docs/releases/0.3.0.md`, iOS 27 adoption) is planned and partially underway. Everything
below 0.3.0 is a proposal, not a commitment — re-baseline each sprint against beta feedback,
since that's the whole point of a beta.

## Now — Sprint 1–2 (finish 0.3.0)

Closing out `docs/releases/0.3.0.md`. Feature and engineering interleave here because the
NowPlaying framework work *is* the engineering lift this release is about.

**Feature**
- [ ] `MediaSessionNowPlayingCenter` (iOS 27 `NowPlaying`/`RadioContent`) verified on-device;
      legacy `MPNowPlayingInfoCenter` path kept as the iOS 26 fallback
- [ ] App Intents entity schemas for favorited stations (Spotlight semantic search)
- [ ] Home-screen quick-play widget (App-Intents-configured favorite station)
- [ ] Reorderable Favorites (iOS 27 list-reordering API)

**Engineering**
- [ ] Lazy-subview prefetch on browse/search station lists
- [ ] Typed throws for playback failures (`AudioStatus.failed(String)` → typed error)
- [ ] Audit `Task { try? … }` call sites once Swift 6.4's unhandled-error warning lands
- [ ] iOS 27 QA checklist (Dynamic Island landscape, resizable-iPhone-app contexts,
      `AsyncImage` HTTP caching, cold-launch re-baseline)

**Exit criteria:** MediaSession path verified with zero regressions vs. legacy; Siri resolves
a favorited station by semantic search; beta 1 crash-free ≥ 99.5% maintained.

## Next — Sprint 3 (0.4.0: beta-2 feature round)

Beta 1's own exit criteria named these as beta-2 candidates; issue #4 (ambient sound on ad
detection) slots in alongside them as the headline feature — it's the first "smart" feature
in an otherwise deliberately dumb-pipe player, so scope it tightly.

**Feature**
- [ ] **Ambient playback on ad detection** (#4): reuse the existing ICY ad-break marker
      detection (`Spot Block Start/End`, already suppressed from displayed titles per the
      0.2.0 metadata-parsing work) as the trigger. Ship a bundled/generated ambient loop
      first (on-device ML nature-sound generation is a real stretch goal, not a v1
      requirement — track separately if it survives scoping); auto-resume the station feed
      when the break ends or the marker stream goes stale. Off by default behind a Settings
      toggle until it's proven not to false-trigger on non-Triton/iHeart stations.
- [ ] Favorites export/import (plain JSON via the Share sheet — no account, no server,
      consistent with the zero-accounts privacy story)
- [ ] Search filters (bitrate, tag/genre, country) on top of Radio-Browser's existing query
      params
- [ ] CarPlay: evaluate whether MediaSession + CarPlay templates can replace
      `MPPlayableContentManager` outright now that the entitlement (applied for in 0.2.0)
      should have landed

**Engineering**
- [ ] Make the headless-test CodeSign workaround (`xattr -cr` + ad-hoc `codesign` +
      `swift test --skip-build`, currently manual per DECISIONS.md) a checked-in script so
      it's one command instead of tribal knowledge, and wire it into CI for RadioDirectory/
      Persistence
- [ ] Get Playback's iOS-only tests (currently `build-for-testing` only, run manually via
      Cmd+U) into an automated simulator test job — this is the biggest gap in the current
      CI (`ci.yml` builds the app but never runs Playback's test target)

**Exit criteria:** ad-break ambient feature doesn't false-trigger across a sample of the top
20 Radio-Browser stations by listener count; beta 2 crash-free ≥ 99.5%; no open P0/P1 for a
week.

## Then — Sprint 4 (engineering hardening)

A sprint with no headline feature, deliberately — 0.2.0 and 0.3.0 both stacked feature work
on top of infra debt (manual UI test runs, no coverage signal, no perf baseline). Pull it
forward before public release rather than after.

- [ ] CI: add a coverage job (`swift test --enable-code-coverage`) and publish a baseline;
      no gate yet, just visibility
- [ ] CI: cold-launch and memory baseline captured per-build (ties into the 0.3.0 QA
      checklist's "30% faster launch" claim, but as an ongoing regression check, not a
      one-time verification)
- [ ] Accessibility audit pass beyond the ad-hoc fixes already shipped (VoiceOver rotor
      order, Dynamic Type XXL on every surface including Settings/About, Reduce Motion on
      the sleep-timer countdown and Live Activity transitions)
- [ ] Dependabot backlog triage (`.github/dependabot.yml` is configured; confirm nothing's
      been silently ignored)
- [ ] Revisit `disabled_rules`/`opt_in_rules` in `.swiftlint.yml` — anything from the 0.2.0
      "ship it" era worth re-enabling now that the tree is lint-clean under `--strict`

## Later — Sprint 5 (public release readiness)

Everything gating a move from TestFlight to the public App Store listing.

**Feature**
- [ ] Professional app icon (0.2.0 shipped a programmatic Core Graphics placeholder,
      explicitly flagged in DECISIONS.md as swap-before-public-release)
- [ ] Community translations beyond English (String Catalog infra shipped in 0.2.0;
      this is populating it)
- [ ] CarPlay templates shipped (if Sprint 3's evaluation said yes)

**Engineering**
- [ ] App Store Connect listing: screenshots, privacy questionnaire, description —
      mirrors `PrivacyInfo.xcprivacy` (zero collection) in the actual store copy
- [ ] Release-process doc: tagging, `GIT_COMMIT_SHA` stamping, GitHub release notes
      generation — currently manual per release, worth a checklist or script once it's
      done three times

## Backlog (unscheduled, revisit each sprint)

- On-device ambient-noise generation for the ad-detection feature (Apple's local ML model,
  if/when a stable API exists) — only after the bundled-loop v1 proves the feature earns
  its complexity
- Home Screen widget variants beyond quick-play (recents, currently-playing)
- Genre auto-tagging for unlabeled stations (explicitly deferred in 0.3.0's "not doing" list
  pending a concrete use case)
- watchOS companion — no current demand signal; don't speculate a design

## How to use this doc

- Re-baseline at the start of every sprint against actual beta/TestFlight feedback — this is
  a proposal, not a schedule external parties are depending on
- When a sprint here graduates from "next" to "now," give it its own
  `docs/releases/X.Y.md` with the same checkbox/exit-criteria structure as 0.2.0/0.3.0, and
  trim this doc back to a one-line pointer at it (see how 0.3.0 already promoted the
  quick-play widget and reorderable favorites out of a backlog note)
- Anything that slips a full sprint without movement should be interrogated, not silently
  rolled forward — either it's blocked (say why) or it's not actually a priority (cut it)

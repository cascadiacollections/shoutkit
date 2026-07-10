# Decisions

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

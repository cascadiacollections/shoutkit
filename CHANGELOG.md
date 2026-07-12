# Changelog

All notable changes to ShoutKit are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- **iPadOS support**: on iPad the root tab bar adopts the sidebar-adaptable style (an Apple
  Music-style sidebar with a built-in toggle back to a top tab bar; iPhone is unchanged), and the
  station lists in Listen Now, Browse, and Search flow into adaptive multi-column grids on wide
  layouts — full-screen iPad, Split View, and Stage Manager — instead of stretching rows across
  the whole window. The app already declared both device families and all four iPad orientations,
  so multitasking and rotation worked before; this makes the layouts native to the space
- **Reorderable Favorites**: the Favorites tab now supports drag-to-reorder. Tap **Edit** (or
  long-press a row) to drag favorites into any order; the arrangement is persisted across launches
  via a new `sortIndex` on the favorite. New favorites append to the bottom so they never disturb
  your ordering, and existing users' lists are re-based from their previous newest-first order on
  first launch, so nothing looks different until you reorder.
- **Live Activity artwork**: the lock screen / Dynamic Island now-playing Live Activity now shows
  the current album (or station) artwork, matching the Now Playing screen and mini-player toolbar.
  Because Live Activity views can't fetch network images, the app downsamples the art into a shared
  App Group container (`group.com.cascadiacollections.shoutkit`) and hands the widget a small token;
  the widget renders the file. Falls back to a playback glyph until art is staged
- **Album art discovery**: when ICY stream metadata contains both artist and title, the app
  queries the iTunes Search API (keyless, best-effort) and shows the resolved album artwork in
  the Now Playing hero, mini-player thumbnail, and lock screen / Control Center. Falls back to
  the station's own artwork if the lookup fails or returns no result. Opt-out via
  **Settings → Privacy → Fetch Album Artwork** (defaults on)
- **Open in Apple Music**: long-press the Now Playing artwork to reveal **View in Apple Music**,
  which opens the matched song in the Apple Music app (or its web player). The link comes from the
  same iTunes Search lookup that resolves album art — no extra network request — so it honors the
  same **Settings → Privacy → Fetch Album Artwork** toggle. The menu appears only when a link is
  found for the current track
- Settings → About shows the build's short git commit next to the version (`0.2.0 (12) · a1b2c3d`),
  so a beta tester's screenshot maps to an exact source revision for bug repro. Stamped at build
  time via the `GIT_COMMIT_SHA` setting; the line stays clean (no commit) for local dev builds
- On iOS 27, lock screen / Control Center / Dynamic Island playback now uses the new NowPlaying
  framework (`MediaSession` + `RadioContent`, WWDC26) with system-managed artwork loading;
  iOS 26 devices keep the proven MediaPlayer path. Selected at runtime — deployment target is
  unchanged
- 0.3.0 release plan (`docs/releases/0.3.0.md`): iOS 27 platform adoption — App Intents entity
  schemas for the new Siri, quick-play widget, and an iOS 27 QA checklist
- **Station Spotlight discoverability**: `StationEntity` now conforms to `IndexedEntity`, and
  the app pushes known stations (favorites, curated, recents) into Spotlight's semantic index
  once per launch, so Siri and system search can resolve "play ⟨station⟩" for a station played
  in a previous session, not only ones searched or played this run. iOS 27's newer
  `AssistantSchema`/`@AssistantEntity` macros are deliberately not adopted yet — their generated
  conformances are `@available(iOS 27, *)` only, which would make `StationEntity` unavailable
  below iOS 27 while the deployment target stays 26 (see `DECISIONS.md`)

### Changed
- **Tighter playback error → user-message mapping**: `PlaybackError` gains two new typed cases —
  `.noInternet` and `.stationNotAvailable(errorCode:)` — mirroring Pocket Casts iOS's
  `PlaybackManager.PlaybackError` pattern. Each case now carries `userMessage` (full-length,
  for the Now Playing screen) and `shortUserMessage` (compact, for the mini player and lock
  screen) computed directly on the type; the UI layer no longer interprets raw error codes or
  supplies fallback strings. `AVPlayerAudioOutput` translates `PlaybackFailure` into the
  appropriate typed case instead of collapsing to `.streamFailed(String)`. `RadioDirectoryError`
  gains the same `userMessage`/`shortUserMessage` pair so `.directory` errors delegate cleanly.
  The mini player now shows the typed short message (e.g. "No connection", "Unavailable") in
  place of the previous hardcoded "Tap to retry"
- **Typed playback failures**: `PlaybackState.failed`/`AudioStatus.failed` carry a new
  `PlaybackError` (`.streamFailed`/`.directory`) instead of a raw `String`, mirroring
  `RadioDirectoryError`'s `errorDescription`/`isRetryable` shape. The bounded auto-reconnect now
  asks the error itself whether a failure is retryable rather than special-casing
  `RadioDirectoryError` inline. No user-visible behavior change
- Adopted swift-async-algorithms (Apple-maintained, Apache-2.0, pinned to a stable release;
  recorded in `THIRD_PARTY_LICENSES.md` and shown in Settings → Licenses), revisiting the
  FOSS audit's initial rejection: `removeDuplicates()` replaces the Live Activity
  coordinator's two hand-rolled duplicate-suppression loops, and Search's 300 ms debounce
  moves from a cancel-and-resleep task to a query stream with `debounce(for:)` — behavior
  unchanged (see `DECISIONS.md`)
- Adopted the first two third-party dependencies after a FOSS audit (both Apple-maintained,
  Apache-2.0, pinned to stable releases; recorded in `THIRD_PARTY_LICENSES.md` and shown in
  Settings → Licenses): swift-algorithms replaces RadioDirectory's three hand-rolled
  de-duplication helpers with `uniqued(on:)`, and swift-collections replaces the Now Playing
  artwork store's dictionary-plus-eviction-order bookkeeping with an `OrderedDictionary`.
  Candidates evaluated and rejected as not paying for themselves: Nuke, GRDB, Defaults,
  Alamofire, and initially swift-async-algorithms — adopted after the wider re-score above
  (see `DECISIONS.md`)
- **Runtime memory hygiene for older devices**: all artwork is now decoded at the size its
  surface actually needs (ImageIO downsampling) instead of the server's native resolution —
  including the lock-screen artwork that stays resident while listening in the background.
  List, card, and mini-player thumbnails moved from `AsyncImage` to a shared thumbnail
  pipeline whose decoded-image cache auto-evicts under system memory pressure; the Now Playing
  artwork store likewise purges when the system signals pressure. The shared URL byte cache is
  explicitly sized (2 MB memory / 64 MB disk), shifting raw-byte caching from RAM to disk and
  letting artwork survive relaunches
- **Background battery hygiene**: playback left paused for 10 minutes now releases the player
  and the audio session (lock-screen controls keep working — play restarts the live stream),
  instead of holding the `audio` background assertion for as long as the app stays paused.
  A stream that stalls buffering for over 90 seconds is likewise parked as paused instead of
  retrying the network indefinitely in the background
- Album-art lookups now also cache definitive catalog misses, so a track iTunes doesn't know
  no longer re-queries the API on every ICY repeat; Now Playing artwork is fetched and decoded
  once per URL and shared across the backdrop, hero, and tint views (previously three decodes)

### Fixed
- **Playback recovery hardening** (comprehensive bug sweep):
  - Pausing during a phone call no longer auto-resumes playback against the user's wish when
    the call ends
  - A failed stream's dead player is torn down before reconnecting, so pause-then-play after a
    mid-play failure restarts the stream instead of silently doing nothing; the give-up path no
    longer keeps the player and audio session resident behind a terminal "failed" state
  - A stream-endpoint lookup that fails mid-reconnect now uses the remaining retry budget
    instead of surfacing failure immediately, and a failed state can always be retried from the
    mini-player and lock screen (previously the active station was forgotten)
  - Unplugging headphones (or a phone call) while a reconnect was pending no longer lets the
    reconnect fire and resurrect audio on the speaker / mid-call
  - A reconnect no longer blanks the last-known track and artwork from the lock screen while
    the stream re-buffers
  - Out-of-order ICY metadata loads can no longer regress the displayed track to the previous
    song; a transient artwork-download failure at play start no longer leaves the lock screen
    artless for the whole session
- **Live Activity correctness**: the lock screen / Dynamic Island activity no longer shows
  "Live" while playback is paused after rapid pause/track-change races (updates are now applied
  in order with the play state tracked at the source), and a superseded artwork download can no
  longer delete the artwork file the activity is currently showing
- **Artwork race fixes**: rapidly switching stations can no longer leave the previous station's
  artwork (or ambient backdrop tint) permanently on the Now Playing screen, and a reused list
  row no longer shows the previous station's logo while the new one loads. The ambient backdrop's
  color mesh was vertically mirrored relative to the artwork for small favicons
- **Directory robustness**: PLS playlist and SHOUTcast XML parsing are now locale-independent
  (they could fail entirely on Turkish-locale devices), a `File1=` playlist entry with no value
  no longer produces a garbage stream URL, searches containing `+` (e.g. "C+C Music Factory")
  are no longer corrupted server-side, permanent directory errors (bad API key) surface
  immediately instead of after a retry backoff, and concurrent mixed-limit top-station fetches
  no longer duplicate requests or downgrade a fresher cache
- The now-playing equalizer animation no longer runs while the app is backgrounded or the screen
  is locked. It was the app's only continuous UI render loop (~8 fps); it now rests whenever the
  scene isn't foreground-active, so hours of background/locked playback do no needless UI work
- Resuming after a stream failure (or after pausing while a station was still loading) no longer
  re-logs the station to recents and re-reports the play to Radio-Browser

## [0.2.0] — in progress (first TestFlight beta)

### Added
- **Sleep timer** in Now Playing (15/30/45/60 minutes) with a live countdown; pauses playback
  when it fires so resuming is one tap
- **Settings & About** (gear on Listen Now): a privacy toggle for Radio-Browser play reporting,
  app version, source/issues/support links, and the full license texts in-app
- A first-run welcome screen shown once on first launch
- An app icon
- Infrastructure for community translations (String Catalogs across every package; English only
  for now)
- Keyless station discovery via Radio-Browser: search, genre browsing, popular stations —
  no API key or account
- Apple Music-style persistent mini-player docked above the tab bar, expanding to a full
  Now Playing surface with live ICY track metadata
- Lock screen / Control Center playback controls and artwork
- Lock screen + Dynamic Island now-playing Live Activity
- Favorites and recents (on-device SwiftData); swipe to remove
- Siri / Shortcuts: "Play ⟨station⟩ on ShoutKit"
- Audio-session interruption and route-change handling (calls pause and auto-resume;
  unplugging headphones pauses)
- Retry buttons on recoverable network failures
- Privacy manifest: no tracking, no data collection
- Project licensing (GPL-3.0 app / MIT packages), DCO contribution policy, CI

### Changed
- Bundle identifier is now `com.cascadiacollections.shoutkit`
- Discovery requests are cached and coalesced (single fetch per launch across tabs)
- The featured-station spotlight banner (Listen Now + Browse) is configured off for beta 1 —
  it was a static first-result pick, not editorial content; the card stays behind a flag
  (`BrowseConfiguration.showsFeaturedSpotlight`) for a possible return

### Fixed
- Raw ICY/broadcaster metadata no longer appears on screen. Rather than whitelisting each
  broadcaster's exact field names, the parser now detects the `key=value` wire format
  structurally — single- or double-quoted, separated by `;`, `,`, *or* a bare space — and only
  ever surfaces recognized title-bearing fields — everything else (e.g. Triton Digital-style
  `TrackId=…,length=…,text=…` cue metadata) is suppressed instead of leaking onto the lock
  screen. Covers classic ICY `StreamTitle='…';StreamUrl='…';`, comma/double-quoted
  `title="…",artist=…` (Z100/iHeartRadio), and both comma- and space-separated `text="…"`
  cue metadata (Z100's ad-break marker `text="Spot Block End" amgTrackId="…" length="…"`);
  handles apostrophes in titles (including tricky cases like `Rock 'n' Roll`), unquoted values,
  and case-insensitive keys. Nested dialects unwrap recursively — iHeart wraps whole cue blocks
  inside `StreamTitle=' - text="…" …';` (captured live from Z100) — ad-break markers
  (`Spot Block Start/End`) show the station name instead of a fake title, and anything that
  still looks like `key="value"` soup after unwrapping is suppressed as a last resort.
  Metadata extraction prefers the explicit title item — never a URL item — from the newest
  timed-metadata group
- ICY titles with an empty artist (`" - Title"`) no longer parse the separator into the title

## [0.1.0] — 2026-06-25

### Added
- Initial scaffold: iOS 26 SwiftUI app shell, modular Swift packages, SHOUTcast directory
  client (key-gated), bundled KEXP streams, basic browse-and-play

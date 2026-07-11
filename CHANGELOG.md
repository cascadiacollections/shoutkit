# Changelog

All notable changes to ShoutKit are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- **Reorderable Favorites**: the Favorites tab now supports drag-to-reorder. Tap **Edit** (or
  long-press a row) to drag favorites into any order; the arrangement is persisted across launches
  via a new `sortIndex` on the favorite. New favorites append to the bottom so they never disturb
  your ordering, and existing users' lists are re-based from their previous newest-first order on
  first launch, so nothing looks different until you reorder
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
- Settings → About shows the build's short git commit next to the version (`0.2.0 (12) · a1b2c3d`),
  so a beta tester's screenshot maps to an exact source revision for bug repro. Stamped at build
  time via the `GIT_COMMIT_SHA` setting; the line stays clean (no commit) for local dev builds
- On iOS 27, lock screen / Control Center / Dynamic Island playback now uses the new NowPlaying
  framework (`MediaSession` + `RadioContent`, WWDC26) with system-managed artwork loading;
  iOS 26 devices keep the proven MediaPlayer path. Selected at runtime — deployment target is
  unchanged
- 0.3.0 release plan (`docs/releases/0.3.0.md`): iOS 27 platform adoption — App Intents entity
  schemas for the new Siri, quick-play widget, and an iOS 27 QA checklist

### Changed
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

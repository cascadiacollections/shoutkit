# Changelog

All notable changes to ShoutKit are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
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

# Changelog

All notable changes to ShoutKit are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org).

> **0.1.0 through 0.3.0 were internal milestones, not releases.** None was ever tagged, and
> no build from them reached a user — the repo had zero git tags until `v0.4.0`. Their
> sections are kept as the development record. `v0.4.0` is the first real release; see
> `docs/RELEASING.md` for how one is cut and `DECISIONS.md` (2026-08-13) for why the
> numbering continues rather than restarting at 1.0.0.

## [Unreleased]

## [0.4.0] — 2026-08-30

### Fixed
- **Playback no longer pops when it rejoins a station after Siri, a TTS announcement, or a
  phone call interrupts it.** Live radio has no position to resume from, so every rejoin
  reconnects at the live edge — but it used to do that at full volume, which read as an
  audible click or jump-cut. It now fades in over a third of a second instead
- **Album art no longer shows as a broken/undefined image on Tesla right after the first
  track of a stream starts.** A station with no artwork of its own had nothing on screen yet
  when the first track's album art resolved, and that "nothing yet" state was mistaken for the
  one case where advertising unfetched art immediately is fine (switching stations). The art is
  now held back until its bytes are actually in hand, same as every other track boundary
- **Spatial Audio no longer crashes the app on launch.** The feature's head-tracking touches
  `CMHeadphoneMotionManager` at bootstrap regardless of whether Spatial Audio is turned on, but
  the app's Info.plist never declared `NSMotionUsageDescription` — iOS aborted the process on
  every launch as a result. The missing usage-description key is added
- **The Apple Watch app now actually installs with the phone app.** It has been built, tested,
  and listed in the README for a month, and no one could get it: nothing bundled it into the
  iPhone app, so there was nothing for your watch to install. It ships inside the app now,
  along with its "Play Last" complication
- **Stations that broadcast a fixed-length programme no longer repeat themselves.** A station
  like NPR's hourly newscast played through to the end and then started over — several times,
  before stopping with an error. The app treated the end of a broadcast the same way it treats a
  live stream dropping, because to a player those look identical. It can tell them apart now: a
  programme that finishes stops, and the play button replays it. If you *want* it to start over,
  Settings → Playback → **Loop Finished Broadcasts** does that; it's off by default, and it has
  no effect on continuous stations, which never end on their own

### Changed
- **VoiceOver now reads the sleep timer's remaining time.** The button announced only that a
  timer was running — the countdown was on screen and nowhere else, so the number that matters
  was available only if you could read it. It now says how long is left, to the nearest minute
  (updating it every second would make VoiceOver talk over itself)
- **The play/pause button grows with your text size.** It was pinned to one size no matter how
  large you set text. It's the main control on the Now Playing screen, and if you've turned text
  up, the buttons were probably hard to hit too
- **Station and track are announced together.** VoiceOver used to stop on the station name, then
  again on the track — on both the Now Playing screen and the mini-player. They're one thought,
  and the second half means nothing on its own
- **Three tabs instead of four**: Browse showed the same popular stations as Listen Now — as a row
  of cards and then again as a list right underneath — and offered the same genre chips as Search.
  Listen Now now carries the full station list under a **More Stations** heading (the stations that
  aren't already in the row of cards above it), and genres live in Search. Nothing is gone: every
  station, genre, and control is still one tap away, just not two places at once
- **Genre chips browse the genre**: tapping "Jazz" in Search used to search for stations whose
  *name* contains "Jazz". It now asks the directory for stations that actually are jazz, and the
  tapped chip stays highlighted so you can see what you're looking at. Clear the search field to
  get back to the full genre list
- **Now Playing is easier to hit**: Stop used to sit right next to play/pause, so a slip ended the
  stream and closed the screen. Play/pause is bigger and centered now, with the favorite heart on
  one side and the sleep timer on the other; Stop and "View in Apple Music" moved into the **⋯**
  menu next to the station name. AirPlay sits on its own at the bottom
- **Recently Played reads correctly at every text size**: the section on Listen Now was drawn at a
  fixed row height, so the last row clipped once you increased text size. To remove a station from
  the list, press and hold it and choose **Remove from Recently Played** (the swipe is gone); the
  **Undo** banner now appears above the mini-player instead of behind it
- **Better contrast in Dark Mode**: the blue accent and the favorited heart were a single fixed
  color tuned for a white background, which left them dim on a dark one. Both now have a dark-mode
  appearance, and station cards use the system's paired background colors so they stay visibly
  distinct from the surface behind them in both appearances
- **ShoutKit now backs off when your battery is low or your data is limited**: the app used to
  fetch artwork for stations you hadn't scrolled to yet, and open connections to your top stations
  at launch, under every condition — including on cellular, in Low Data Mode, and in Low Power
  Mode. Both are guesses about what you'll do next, so both now stop when the device is trying to
  conserve, and neither ever uses your cellular allowance for a guess. Nothing you actually look at
  or listen to is affected: artwork for stations on screen, the station directory, and playback
  itself are unchanged
- **Stations are there the moment you open the app**: Listen Now now saves the
  station list to disk and paints it instantly on the next launch, instead of showing
  "Tuning in…" while the directory answers. Within six hours of the last successful update the
  saved list is used as-is and no request is made at all, so opening the app repeatedly shows the
  same stations rather than a reshuffled ranking. Pull to refresh (or leave the app for a few
  hours) to get a fresh list
- **The station list survives losing your connection**: if the directory can't be reached, the
  saved stations stay on screen with a short "showing saved stations" note, rather than being
  replaced by a "Directory Unavailable" page. The error page now only appears when there's nothing
  saved yet — a first launch with no connection. Favorites, recents, and playback were already
  offline-capable and are unchanged. Genre chips still need a connection
- **iOS 27 now-playing surface**: on iOS 27 the lock screen / Control Center / Dynamic Island
  now-playing surface is driven by the new typed `MediaSession` / `RadioContent` framework instead
  of the legacy `MPNowPlayingInfoCenter` bridge; iOS 26 is unchanged. Transport controls, artwork,
  and live track metadata behave the same — the change is internal, selected by OS version
- **Smoother list scrolling**: the Listen Now and Search station lists now prefetch artwork for
  rows about to scroll into view, so thumbnails are decoded ahead of time instead of stalling as
  each row appears. Repeated loads of the same artwork are also coalesced so a prefetch and a
  visible row never fetch the same image twice

### Added
- **Top Tracks**: the Library tab now shows your most-played songs — over the last week, the
  last month, or all time — with cover art where it's available, right alongside Recently
  Heard
- **Apple TV app**: ShoutKit on tvOS, built for the Siri Remote — a now-playing banner over
  Recent and Popular station shelves, with play/pause and stop, and the system Now Playing panel
  (TV button) showing artwork and responding to the remote's transport controls. It runs the same
  audio engine as the iPhone app, so the current track's title and artist appear alongside the
  station name; stations that send no track information show their genre instead. Recents come
  from the Apple TV itself — there is no sync with your phone
- **Home Screen quick-play widget**: a small/medium Home Screen widget that plays a favorite
  station in one tap. Long-press → **Edit Widget** to choose which favorite it plays (it falls back
  to your first favorite until you pick one); tapping the tile opens ShoutKit straight onto that
  station and starts playback via the same `shoutkit://station?…` deep link Shortcuts uses. The app
  mirrors your favorites to the widget through the shared App Group and refreshes it whenever the
  list changes or is reordered
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
- **Album art reaches car stereos over Bluetooth again**: track titles and artists were arriving
  fine, but the artwork either never changed or stayed on whatever was playing before ShoutKit —
  an album cover left over from Apple Music, for instance. A car receives cover art on a separate,
  slow channel *after* it is told the track changed, so it needs the image ready at that moment and
  it needs to be told once, not twice. ShoutKit was doing neither: it only started downloading
  artwork when the system asked for it (with a forced network round-trip in front of every
  request), and it announced a track change twice per song — once with the station's logo the
  instant a new title arrived, then again with the real cover a moment later. Artwork is now
  downloaded and held in memory before the track change is announced, and the announcement happens
  once, with the cover already in hand. The station's own logo still stands in for tracks with no
  cover art, and lock-screen and CarPlay behaviour is unchanged
- **Stations that stream over plain http now play**: a misspelled App Transport Security key meant
  the app's cleartext exception was silently ignored, so any station whose stream isn't served over
  https was blocked by iOS before a single byte arrived. A large share of the Radio-Browser and
  SHOUTcast catalogue is http-only, and those stations simply failed to start. Everything ShoutKit
  itself talks to — the directory, artwork, the album-art lookup — remains https
- **Scrolling a carousel or swiping a row no longer jumps you to another tab**: a swipe-between-tabs
  gesture on the root view ran alongside, rather than instead of, whatever you were actually
  swiping, so dragging the Popular Stations carousel, swiping a station away in Favorites or Listen
  Now, or swiping back from a genre could all switch tabs. Tabs are now changed by tapping them, as
  in Apple Music
- **Search no longer gets stuck on the spinner**: typing a trailing space (or accepting an
  autocorrection) while a search was still running cancelled it without starting a new one, leaving
  the spinner up until the query was edited again
- **Notifications, calls, and Siri no longer strand your station**: an ordinary notification now
  ducks live radio for its sound instead of pausing it outright, and when a real interruption
  (call, alarm, Siri) ends, playback comes back even in the cases where iOS doesn't tell the app
  it should — as long as nothing else has started playing meanwhile and the interruption was
  short. Pausing during a call still means paused when it ends, and an interruption that starts
  while you're already paused can no longer cause playback to start itself later
- **Playback survives the system refusing the audio session**: resuming right after a call or
  Siri could leave the app showing "playing" with no sound, because the audio session activation
  failed and the failure was ignored. Activation is now verified and retried briefly, and a
  stream is only started once the session is really active — otherwise it reconnects
- **An audio-server restart no longer needs an app relaunch**: if iOS resets media services
  mid-listen (which invalidates every audio object in the app), playback used to go permanently
  silent. The player and audio session are now rebuilt and the station rejoined automatically
- Unplugging headphones while nothing was playing no longer replaces an on-screen playback error
  with a silent paused state, or cancels a reconnect that was already in flight
- iOS playback now declares itself as long-form audio (like the watch app already did), which is
  what the system uses for AirPlay 2 routing and volume handling on shared routes
- Album artwork now appears on Tesla and other strict Bluetooth AVRCP clients by returning cover
  art at the exact dimensions requested by the connected device
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
- **Play/pause no longer gets stuck after a pause**: tapping play after a pause could do nothing
  at all — no audio, no error — leaving the only way out switching to another station and back.
  The streaming engine refuses to resume a player whose stream is already gone, and did so
  silently, which happened whenever its own state had drifted from the app's: the system stops the
  audio engine for an interruption (call, Siri, alarm) without informing it, and a live stream the
  server closes ends the same way. Now:
  - An interruption pauses the engine as well as the app's state machine, so the two can't drift
  - A live stream the server drops is surfaced instead of swallowed, so the app reconnects rather
    than showing a dead stream as playing
  - A resume the engine doesn't act on within a couple of seconds rejoins the stream — the
    switch-stations workaround, done automatically, for any playback backend
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

## [0.2.0] — milestone, never released (planned as the first TestFlight beta)

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

## [0.1.0] — milestone, never released (dated 2026-06-25)

### Added
- Initial scaffold: iOS 26 SwiftUI app shell, modular Swift packages, SHOUTcast directory
  client (key-gated), bundled KEXP streams, basic browse-and-play

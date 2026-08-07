# ShoutKit

ShoutKit is a native SwiftUI internet-radio client for iOS and iPadOS 27+. It ships with real,
keyless station discovery out of the box via [Radio-Browser](https://www.radio-browser.info) — a
free, open-source community radio directory — plus an Apple Music-style persistent player: a Liquid
Glass mini-player docked above the tab bar, a full-screen Now Playing surface with live ICY track
metadata, lock-screen/Control Center controls, favorites and recents backed by SwiftData, and
Siri/Shortcuts support ("Play KEXP on ShoutKit"). On iPad the tab bar becomes a sidebar and
browsing surfaces flow into adaptive multi-column layouts, including Split View and Stage Manager.

## Requirements

- Xcode 27 with the iOS 27 SDK
- Swift 6 strict concurrency
- iOS / iPadOS 27.0+ deployment target

If your active developer directory points at Command Line Tools, build with:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -workspace ShoutKit.xcworkspace -scheme ShoutKit -destination 'generic/platform=iOS Simulator' build
```

## Station discovery

Discovery works with **zero configuration**: `AppDependencies` defaults to
`RadioBrowserDirectoryClient`, which talks to Radio-Browser's DNS-load-balanced community mirrors
(`all.api.radio-browser.info`, with named-mirror fallback). Search, genre browsing, and popular
stations all come from there — no API key. Per Radio-Browser etiquette the app sends a descriptive
User-Agent and reports plays (`/json/url/{stationuuid}`) so the community directory can rank
popularity; only Radio-Browser-sourced stations (UUID ids) are reported.

Every directory is wrapped in `PreferredRadioDirectory`, so curated stations are guaranteed even
when a directory source omits them — KEXP is bundled using its official 160K/64K AAC stream URLs.
`PreviewRadioDirectory` is reserved for previews and tests.

### Stations without the wait

Discovery content is cached in two tiers by `CachingRadioDirectory`. A 60-second in-memory window
coalesces the discovery fetches issued around launch, and every successful fetch is also
written to a small JSON snapshot in Application Support. Landing surfaces paint that snapshot
first, so a launch shows stations immediately rather than a spinner, and within a six-hour
stability window the snapshot *is* the answer — no directory request at all, and the same list as
the previous launch instead of a reshuffled top-click ranking. Pull-to-refresh and the four-hourly
`BGAppRefreshTask` both bypass the window and rewrite the snapshot.

The live calls (`topStations`, `genres`) never serve the snapshot; the saved copy is reachable only
through the `DirectoryDiscoveryCaching` seam, so a surface always knows whether it's showing live
or saved content. When the directory can't be reached, saved stations stay on screen with a note
rather than being replaced by an error — the error state is reserved for having nothing to show.
Snapshots are scoped by directory source and geo filter, so travelling (or toggling the
geo-stations flag) refetches instead of serving another region's stations. Favorites and recents
are separately offline-capable via SwiftData; search results and per-genre lists are user-driven
and deliberately not persisted.

### Optional: SHOUTcast directory

To use SHOUTcast's own directory instead of Radio-Browser, supply a developer key. The app reads
`SHOUTCAST_DEV_KEY` from build settings into `Info.plist`; do not hard-code this value.

1. Copy `ShoutKitApp/Config/Secrets.xcconfig.template` to `ShoutKitApp/Config/Secrets.xcconfig`.
2. Set:

```xcconfig
SHOUTCAST_DEV_KEY = your_key_here
```

`Secrets.xcconfig` is intentionally ignored by Git. With a key present,
`AppDependencies` creates `ShoutcastDirectoryClient`, which fetches live genre/top/search data from
`api.shoutcast.com/legacy/...` and resolves station streams through
`yp.shoutcast.com/sbin/tunein-station.pls`.

## Architecture

- `ShoutKitApp`: thin SwiftUI app targets — the iPhone/iPad app keeps app-level wiring in
  `AppDependencies.bootstrap()` (shared between the scene and App Intents), while the watch app
  carries a separate minimal service graph for native watch playback. The phone app provides the
  3-tab root shell (Listen Now · Search · Favorites) with the persistent mini-player and
  Siri/Shortcuts (`PlayStationIntent` with a station entity resolved from favorites, recents,
  curated stations, and live search); the watch companion focuses on now playing, recent stations,
  and a complication quick-start path.
- `Packages/DesignSystem`: Liquid Glass-aware reusable SwiftUI surfaces (station rows/cards/
  carousel, artwork, playing indicator) and design tokens, with Reduce Transparency/Increase
  Contrast fallbacks.
- `Packages/RadioDirectory`: domain models, the `RadioDirectoryProviding` boundary, the
  Radio-Browser JSON client (default), the SHOUTcast XML client (optional, key-gated), and the
  curated/bundled directories.
- `Packages/Playback`: `PlaybackController` (app-wide observable playback state), the
  `RadioPlaybackEngine` seam it drives, ICY metadata parsing, the sleep timer, and a
  `NowPlayingPresenting` bridge that targets either
  `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` (iOS 26) or the iOS 27
  `NowPlaying`/`MediaSession` framework, selected at runtime. Ships no engine itself, which is
  what keeps it free of a codec dependency.
- `Packages/PlaybackEngineAudioStreaming`: the production `RadioPlaybackEngine` —
  `AudioStreamingPlaybackEngine`, AVAudioEngine-backed via the MIT-licensed
  [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) library — with audio-session
  ownership (interruptions, route changes, media-services reset) and the equalizer attach point.
  iOS-only and linked by the app target alone: AudioStreaming pulls the ogg/vorbis xcframeworks,
  which have no watchOS slice, and SwiftPM fetches binary artifacts regardless of platform
  conditions. The watch app supplies its own `AVPlayer`-backed engine.
- `Packages/Persistence`: SwiftData models and `LibraryStore` for favorites and recents.
- `Packages/LiveActivity`: Live Activity attributes and the `NowPlayingActivityCoordinator`
  driving the lock screen / Dynamic Island now-playing surface, including staging downsampled
  artwork into a shared App Group container for the widget extension to render.
- `Packages/ImageIODownsample`: a small leaf module wrapping ImageIO downsampling, shared by
  `DesignSystem`'s artwork pipeline and Live Activity artwork staging so decoded images never
  exceed the pixel size their surface actually needs.
- `Packages/Features/*`: one package per tab surface.

Dependency wiring across these packages goes through [Factory](https://github.com/hmlongco/Factory)
(`Container`-based DI) rather than direct instantiation, so tests and previews can substitute fakes
without touching production call sites. Debug builds also link an app-side `DebugSupport` package
(`#if DEBUG`-only [Pulse](https://github.com/kean/Pulse) network inspection); it's never declared
by the reusable packages and is compiled out of Release entirely. See
[`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md) for the full dependency list.

The app uses SwiftUI, Observation, SwiftData, async/await, and local Swift packages. View state
lives in `@Observable` `@MainActor` models, while networking, playback, and persistence
implementation details stay behind protocol or actor boundaries.

## Capabilities

The phone app `Info.plist` declares `UIBackgroundModes = audio` for streaming playback and
`NSSupportsLiveActivities` for the lock screen / Dynamic Island now-playing Live Activity (the
`ShoutKitWidgets` extension target, driven by `NowPlayingActivityCoordinator` from playback
state, with synced album/station artwork). The watch app adds a native watchOS now-playing +
recents surface plus a one-tap "Play Last" complication that deep-links into watch playback.
App Intents power Siri/Shortcuts with headless background playback (no app foregrounding);
`StationEntity` also conforms to `IndexedEntity` so favorited, curated, and recently-played
stations land in Spotlight's semantic index, letting Siri resolve "play ⟨station⟩" for a station
from a previous session. `shoutkit://station?...` deep links open the phone app to a station for
promos, notifications, and other launch entry points; the app also publishes an `NSUserActivity`
for the current station so Handoff can resume it on another signed-in device; and long-pressing
Now Playing artwork
surfaces a "View in Apple Music" link when a track match is found. A small/medium Home Screen
widget plays a chosen favorite in one tap, and **CarPlay** ships as a `CPListTemplate` of
favorites and recents over `CPNowPlayingTemplate`, driven by the same `PlaybackController` (the
`com.apple.developer.carplay-audio` entitlement is declared in
`ShoutKitApp/ShoutKitApp.entitlements`). What's still ahead is in
[`docs/ROADMAP.md`](docs/ROADMAP.md).

## Privacy

ShoutKit collects nothing and tracks nothing. There are no analytics, no ads, and no accounts.
The app's privacy manifest (`PrivacyInfo.xcprivacy`) declares zero collected data types and no
tracking. The complete list of network traffic the app produces:

- **Directory queries** to [Radio-Browser](https://www.radio-browser.info) community mirrors
  (or `api.shoutcast.com` if you opt into a SHOUTcast key): search terms, genre names, and
  station lookups — the same requests any client of those public directories makes.
- **Play reports** to Radio-Browser (`/json/url/{stationuuid}`) when you play a
  Radio-Browser-sourced station, per that project's etiquette, so the community directory can
  rank station popularity. Only the station's public UUID is sent — nothing about you or your
  device beyond a generic `ShoutKit/x.y` User-Agent.
- **Stream and artwork fetches** directly from the stations you choose to play.

Favorites and recents live in a local SwiftData store on your device, alongside a small snapshot of
the public station list the landing surfaces last fetched (so they can render without a network
round trip). Nothing about you is stored in either, and nothing leaves the device.

## Roadmap

Release plans live in `docs/releases/*.md`; the sprint-by-sprint sequencing across releases
is in [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Testing

All package test suites (`RadioDirectory`, `Playback`, `Persistence`) run on the mac host with
`swift test` — the iOS-only playback types are `canImport(UIKit)`-gated so the controller tests
execute against fakes anywhere. See [CONTRIBUTING.md](CONTRIBUTING.md) for details and a local
codesign workaround.

## Licensing

| Component | License |
|---|---|
| App target (`ShoutKitApp`, incl. the debug-only `DebugSupport` package), feature packages (`Packages/Features/*`), `Packages/LiveActivity`, `Packages/ImageIODownsample` | [GPL-3.0](LICENSE) |
| `Packages/RadioDirectory`, `Packages/Playback`, `Packages/PlaybackEngineAudioStreaming`, `Packages/Persistence`, `Packages/DesignSystem` | [MIT](Packages/RadioDirectory/LICENSE) (per-package `LICENSE` files) |

The reusable infrastructure packages are MIT so they can be adopted anywhere; the app itself is
GPL-3.0 so distributed forks must remain open source. The **ShoutKit name and branding are not
covered by the code licenses** — see [TRADEMARK.md](TRADEMARK.md). Contributions require a DCO
sign-off; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Supporting the project

ShoutKit is free software built in the open. If it's useful to you, support development via the
funding links in [`.github/FUNDING.yml`](.github/FUNDING.yml) (GitHub's Sponsor button). The app
itself contains no paywalls — everything works whether or not you donate.

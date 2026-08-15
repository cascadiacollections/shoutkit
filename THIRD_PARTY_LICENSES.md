# Third-Party Licenses

ShoutKit's runtime dependencies are listed here with their licenses. Every
entry must be GPL-3.0-compatible (MIT, Apache-2.0, BSD); GPL/LGPL/AGPL and
unlicensed code are not accepted. Dependencies are pinned to stable semver
releases — never branch references. When adding one, record it here and, since
it ships in the binary, add its license text to the in-app Licenses screen
(`SettingsFeature`).

| Name | Version | License | Used in | URL |
| ---- | ------- | ------- | ------- | --- |
| swift-algorithms | 1.2.1+ (`from: "1.2.1"`) | Apache-2.0 (with Runtime Library Exception) | RadioDirectory — order-preserving, case-insensitive de-duplication (`uniqued(on:)`) of merged station/genre lists | <https://github.com/apple/swift-algorithms> |
| swift-async-algorithms | 1.1.5+ (`from: "1.1.5"`) | Apache-2.0 (with Runtime Library Exception) | SearchFeature — `debounce` on the query stream; LiveActivity — `removeDuplicates()` on the playback-state and track-metadata observation sequences | <https://github.com/apple/swift-async-algorithms> |
| swift-collections | 1.6.0+ (`from: "1.6.0"`) | Apache-2.0 (with Runtime Library Exception) | DesignSystem — `OrderedDictionary` backs the Now Playing artwork store's bounded FIFO cache | <https://github.com/apple/swift-collections> |
| swift-numerics | 1.1.1 (transitive via swift-algorithms) | Apache-2.0 (with Runtime Library Exception) | Transitive only — `RealModule` dependency of swift-algorithms; no direct ShoutKit use | <https://github.com/apple/swift-numerics> |
| Factory | 3.3.2 (`exact: "3.3.2"`; `from: "3.3.2"` in Persistence) | MIT | RadioDirectory, Playback, PlaybackEngineAudioStreaming, Persistence, FeatureFlags, BrowseFeature, BrowseFeatureCore, SearchFeature, SearchFeatureCore — `Container`-based dependency injection | <https://github.com/hmlongco/Factory> |
| AudioStreaming | 1.4.4 (`exact: "1.4.4"`) | MIT | PlaybackEngineAudioStreaming — `AudioStreamingPlaybackEngine`, the `AVAudioEngine`-backed production playback engine (iOS only) | <https://github.com/dimitris-c/AudioStreaming> |
| ogg-binary-xcframework | 0.1.2 (transitive via AudioStreaming) | BSD (Xiph.org) | PlaybackEngineAudioStreaming — libogg, linked by AudioStreaming's Ogg Vorbis codec support | <https://github.com/sbooth/ogg-binary-xcframework> |
| vorbis-binary-xcframework | 0.1.2 (transitive via AudioStreaming) | BSD (Xiph.org) | PlaybackEngineAudioStreaming — libvorbis, linked by AudioStreaming's Ogg Vorbis codec support | <https://github.com/sbooth/vorbis-binary-xcframework> |

## Development-only tools

Not linked into the shipped binary; listed for completeness.

| Name | License | Used for | URL |
| ---- | ------- | -------- | --- |
| SwiftLint (pinned in CI, see `ci.yml`) | MIT | Linting, `--strict` in CI | <https://github.com/realm/SwiftLint> |
| SwiftFormat | MIT | Formatting (`.swiftformat`) | <https://github.com/nicklockwood/SwiftFormat> |
| Pulse | MIT | DebugSupport (app-side package) — `#if DEBUG`-only network inspection (`DebugNetworkInspection.swift`); never declared by the reusable packages, compiled out of Release entirely (CI symbol-checks this), and attributed in the in-app Licenses screen of Debug builds since testers do receive it | <https://github.com/kean/Pulse> |

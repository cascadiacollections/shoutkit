# Third-Party Licenses

Holmdel's runtime dependencies are listed here with their licenses. Every
entry must be GPL-3.0-compatible (MIT, Apache-2.0, BSD); GPL/LGPL/AGPL and
unlicensed code are not accepted. Dependencies are pinned to stable semver
releases — never branch references. When adding one, record it here and, since
it ships in the binary, add its license text to the in-app Licenses screen
(`SettingsFeature`).

| Name | Version | License | Used in | URL |
| ---- | ------- | ------- | ------- | --- |
| swift-collections | 1.7.5+ (`from: "1.7.5"`) | Apache-2.0 (with Runtime Library Exception) | DesignSystem — `OrderedDictionary` backs the Now Playing artwork store's bounded FIFO cache | <https://github.com/apple/swift-collections> |
| Factory | 3.5.2 (`exact: "3.5.2"` in every manifest) | MIT | RadioDirectory, Playback, PlaybackEngineAudioStreaming, Persistence, FeatureFlags, BrowseFeature, BrowseFeatureCore, SearchFeature, SearchFeatureCore — `Container`-based dependency injection | <https://github.com/hmlongco/Factory> |
| AudioStreaming | 1.4.5 (`exact: "1.4.5"`) | MIT | PlaybackEngineAudioStreaming — `AudioStreamingPlaybackEngine`, the `AVAudioEngine`-backed production playback engine (iOS only) | <https://github.com/dimitris-c/AudioStreaming> |
| ogg-binary-xcframework | 0.1.2 (transitive via AudioStreaming) | BSD (Xiph.org) | PlaybackEngineAudioStreaming — libogg, linked by AudioStreaming's Ogg Vorbis codec support | <https://github.com/sbooth/ogg-binary-xcframework> |
| vorbis-binary-xcframework | 0.1.2 (transitive via AudioStreaming) | BSD (Xiph.org) | PlaybackEngineAudioStreaming — libvorbis, linked by AudioStreaming's Ogg Vorbis codec support | <https://github.com/sbooth/vorbis-binary-xcframework> |

## Development-only tools

Not linked into the shipped binary; listed for completeness.

| Name | License | Used for | URL |
| ---- | ------- | -------- | --- |
| SwiftLint (pinned in CI, see `ci.yml`) | MIT | Linting, `--strict` in CI | <https://github.com/realm/SwiftLint> |
| SwiftFormat | MIT | Formatting (`.swiftformat`) | <https://github.com/nicklockwood/SwiftFormat> |
| Pulse | MIT | DebugSupport (app-side package) — `#if DEBUG`-only network inspection (`DebugNetworkInspection.swift`); never declared by the reusable packages, a dynamic framework that Release neither loads nor embeds (CI checks this), and attributed in the in-app Licenses screen of Debug builds since testers do receive it | <https://github.com/kean/Pulse> |

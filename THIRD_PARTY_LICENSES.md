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

## Development-only tools

Not linked into the shipped binary; listed for completeness.

| Name | License | Used for | URL |
| ---- | ------- | -------- | --- |
| SwiftLint (pinned in CI, see `ci.yml`) | MIT | Linting, `--strict` in CI | <https://github.com/realm/SwiftLint> |
| SwiftFormat | MIT | Formatting (`.swiftformat`) | <https://github.com/nicklockwood/SwiftFormat> |

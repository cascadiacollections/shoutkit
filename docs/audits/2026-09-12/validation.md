# Audit validation

Date: 2026-09-12. Audited source SHA: `9cd7f0d8929746b2baf3598746a43b872e517839`.
Toolchain: Xcode 27.0 (27A266a).

## Initial evidence

| Check | Result |
|---|---|
| Playback host suite before fixes | PASS — 187 tests, 20 suites |
| Temporary `AuditBoundaryTests` before fixes | FAIL as expected — 4 tests, 5 assertions |
| Initial unsigned Release build | PASS |

The original reproduction source and failure output remain beside this file as
`AuditBoundaryTests.swift.txt` and `boundary-tests.log`.

## Implementation validation

| Check | Result |
|---|---|
| Playback: `swift test --disable-xctest` | PASS — 194 tests, 21 suites |
| Permanent intent-boundary regressions | PASS — 6 tests |
| RadioDirectory: `swift test --disable-xctest` | PASS — 71 tests, 9 suites |
| `swiftlint --strict` | PASS — 222 Swift files |
| Localization catalogs parsed as JSON | PASS |
| Holmdel unsigned Debug build, generic iOS Simulator | PASS — includes iPhone and embedded watch targets |
| Holmdel unsigned Release build, generic iOS Simulator | PASS |
| Full iOS simulator test plan | INCONCLUSIVE — Xcode 27 waited after app validation without launching a test process; stopped after 150 seconds |
| Visual simulator walkthrough | Not performed — the host UI was locked |
| Physical device, installed TestFlight binary and audio-route matrix | Not performed |

The Playback run retains one pre-existing compiler warning in
`PlaybackEndOfStreamTests` about a mutable value captured by a sendable closure. It does not
fail the suite or arise from the audit changes.

Production changes address the eight source findings. Physical audio routing, interruption
behavior on hardware, battery use, actual audible latency and the installed TestFlight build
still require the acceptance matrix in `playback-ux-audit.md`; simulator success cannot prove
those properties.

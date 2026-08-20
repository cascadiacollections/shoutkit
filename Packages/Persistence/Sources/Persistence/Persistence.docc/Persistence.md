# ``Persistence``

Favorites, recents, settings, and listening history, on top of SwiftData.

## Overview

`Persistence` holds the app's local stores: ``LibraryStore`` for favorites and recently played
stations, ``SettingsStore`` for user preferences, and a diagnostics pipeline that records
MetricKit payloads into GRDB.

Build a model container, then a store over it:

```swift
let container = ShoutKitModelContainer.makeContainer()
let library = LibraryStore(context: ModelContext(container))
```

### Errors are reported, not thrown

Mutating operations on ``LibraryStore`` return `Void` and swallow their failures into
``LibraryStore/lastErrorMessage``, rather than throwing. That keeps SwiftUI call sites free of
`try`, and it means a caller that needs to know whether a write succeeded must read that
property afterwards.

### Scope

Two things in here are narrower than the package name suggests, and are worth knowing before
you adopt it: ``RecentlyPlayedTeaserState`` is view-model state for a specific carousel rather
than a store, and ``SettingsStore`` carries audio-feature toggles (spatial audio, stream
looping, equalizer preset) that belong to this app's feature set. `SettingsStore` also writes
to `UserDefaults.standard` under unprefixed `settings.*` keys, which can collide in a host app
that shares the suite.

## Topics

### Model Container

- ``ShoutKitModelContainer``

### SwiftData Models

- ``FavoriteStation``
- ``RecentStation``
- ``RecentlyHeardTrack``

### Top Tracks

- ``TopTrack``
- ``TopTracksTimeframe``
- ``TopTracksAggregator``

### Stores

- ``LibraryStore``
- ``SettingsStore``
- ``DefaultsKey``

### Diagnostics

- ``DiagnosticsServicing``
- ``DiagnosticsService``
- ``NoopDiagnosticsService``
- ``DiagnosticsPayloadPersisting``
- ``DiagnosticsPayloadStore``
- ``DiagnosticsPayloadStoreError``
- ``DiagnosticsMetricPayloadSummary``
- ``DiagnosticsAppLaunchSummary``
- ``DiagnosticsNetworkTransactionSummary``

### View State

- ``RecentlyPlayedTeaserState``

### Test Support

- ``InMemoryDiagnosticsPayloadStore``

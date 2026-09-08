# ``DesignSystem``

SwiftUI surfaces and design tokens for radio browsing.

## Overview

`DesignSystem` provides the station-shaped views the app is built from — rows, cards, carousels,
hero artwork — plus the tokens (``ShoutKitSpacing``, ``ShoutKitRadius``, colors, fonts) they are
drawn with, and the artwork loading pipeline behind them.

### Before you adopt this

Two constraints are larger than they look:

- **iOS 26 only.** `Package.swift` declares `.iOS(.v26)` and no other platform. Views here use
  `glassEffect`, `.buttonStyle(.glassProminent)`, and `MeshGradient`, none of which back-deploy.
  This is also why the package does not build on a Mac host, and therefore why the
  `*FeatureCore` packages exist to hold testable logic.
- **It depends on the domain layer.** `RadioDirectory` and `Playback` appear in public
  signatures — ``StationRow`` takes a `Station` and a `StationPlaybackPhase`,
  ``DirectoryUnavailableView`` takes a `RadioDirectoryError`. Roughly a third of the public
  views are domain-free; the rest bring the station stack with them.

### Isolation

The target is built with `.defaultIsolation(MainActor.self)`, so every type here is
`@MainActor` even where no annotation appears in the source. The exceptions opt out explicitly.

### Localization

This package ships its own string catalog. Any string literal added here must go through
`String(localized:bundle: .module)` — a bare `LocalizedStringKey` in a package resolves against
the *app's* bundle, so this catalog is never consulted and the string ships untranslated.

## Topics

### Station Surfaces

- ``StationRow``
- ``StationRowAction``
- ``StationCard``
- ``StationCarousel``
- ``SectionHeaderView``

### Artwork

- ``StationArtworkView``
- ``HeroArtworkView``
- ``AmbientArtworkBackdrop``
- ``ArtworkLoader``
- ``ArtworkLoadPolicy``
- ``ArtworkLoadRequest``
- ``LoadedArtwork``

### Design Tokens

- ``ShoutKitSpacing``
- ``ShoutKitRadius``
- ``ShoutKitLayout``

### Controls and States

- ``GlassControlSurface``
- ``PlayingIndicator``
- ``DirectoryUnavailableView``

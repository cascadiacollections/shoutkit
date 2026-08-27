// `os(iOS)` rather than `canImport(UIKit) && !os(watchOS)`: the latter reads as
// "iOS" but is also true on tvOS and visionOS, where the Factory-resolved engine
// below has nothing registered over it. A tvOS target would silently inherit this
// initializer, resolve `StubRadioPlaybackEngine`, and play silence — the failure
// mode CLAUDE.md warns about for engine registration. A new platform gets its own
// explicit wiring (as watchOS does) instead of inheriting this one by accident.
#if os(iOS)
import FactoryKit
import Foundation
import RadioDirectory

public extension PlaybackController {
    /// Production wiring: the Factory-resolved playback engine (see
    /// ``Container/radioPlaybackEngine``) and the OS-selected system now-playing
    /// center (see ``makeSystemNowPlayingCenter``).
    ///
    /// The engine resolves to ``StubRadioPlaybackEngine`` unless something has
    /// registered over it, so an app using this initializer must call
    /// `registerProductionPlaybackEngine()` from `PlaybackEngineAudioStreaming`
    /// first — `AppDependencies.bootstrap()` does, before constructing the
    /// controller.
    convenience init(directory: any RadioDirectoryProviding) {
        self.init(
            directory: directory,
            output: Container.shared.radioPlaybackEngine(),
            nowPlayingCenter: Self.makeSystemNowPlayingCenter()
        )
    }

    /// Selects the system now-playing surface (lock screen / Control Center /
    /// Dynamic Island) by OS version:
    ///
    /// - **iOS 27+** → ``MediaSessionNowPlayingCenter``: the typed, observable
    ///   `MediaSession` path with `RadioContent` and structured `MediaCommand`s.
    /// - **iOS 26** → ``NowPlayingCenter``: the legacy `MPNowPlayingInfoCenter` /
    ///   `MPRemoteCommandCenter` bridge.
    ///
    /// Both conform to ``NowPlayingPresenting`` (the seam added for testability in
    /// 0.2.0), so the controller, its tests, and the fakes are untouched by the
    /// switch. This is a first-beta framework: if the MediaSession path misbehaves
    /// in TestFlight, deleting the `#available` branch collapses selection back to
    /// the legacy path.
    static func makeSystemNowPlayingCenter() -> any NowPlayingPresenting {
        #if canImport(NowPlaying)
        // Every platform this package declares is named explicitly; the bare `*`
        // means "available from *this* platform's deployment target", so it silently
        // becomes wrong the moment a platform exists at a floor below the version the
        // symbols need. That is exactly how the watchOS 26 floor drop broke this
        // check (DECISIONS.md 2026-08-12), and naming tvOS 27 keeps a tvOS floor of
        // 26 from reintroducing it.
        if #available(iOS 27, tvOS 27, watchOS 27, *) {
            return MediaSessionNowPlayingCenter()
        }
        #endif
        return NowPlayingCenter()
    }

    /// A controller wired to preview data for SwiftUI previews.
    static func preview() -> PlaybackController {
        PlaybackController(directory: PreviewRadioDirectory())
    }
}
#endif

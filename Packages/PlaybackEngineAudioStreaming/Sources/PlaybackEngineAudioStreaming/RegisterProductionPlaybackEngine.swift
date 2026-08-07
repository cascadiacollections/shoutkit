import FactoryKit
import Playback

/// Registers the AudioStreaming-backed engine as the shared resolution for
/// `Container.radioPlaybackEngine`.
///
/// A free function for the same reason as `registerProductionRadioDirectory(_:)`
/// in `RadioDirectory`: the app target overrides a Factory registration without
/// importing `FactoryKit` itself, so the DI library stays an implementation
/// detail of the packages that chose it.
///
/// **Ordering matters.** `PlaybackController`'s production
/// `init(directory:)` resolves the engine through Factory, so this must run
/// before the first controller is constructed — `AppDependencies.bootstrap()`
/// calls it alongside `installSharedNetworking()`, which has the same
/// before-anything-else contract. Without it the app silently resolves
/// `StubRadioPlaybackEngine` and plays nothing.
///
/// Registered under `.singleton` scope by the declaration in `Playback`, so
/// calling this more than once is harmless; `bootstrap()` is itself idempotent.
@MainActor
public func registerProductionPlaybackEngine() {
    Container.shared.radioPlaybackEngine.register { AudioStreamingPlaybackEngine() }
}

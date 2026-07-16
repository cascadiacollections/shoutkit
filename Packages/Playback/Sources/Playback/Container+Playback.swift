import FactoryKit

public extension Container {
    /// The playback engine backing ``PlaybackController``, resolved via Factory
    /// instead of direct instantiation. AudioStreaming-backed on iOS; falls back
    /// to ``StubRadioPlaybackEngine`` where that's unavailable (the mac host test
    /// target). `@MainActor` because `AudioOutput` (and therefore
    /// `RadioPlaybackEngine`) is.
    @MainActor
    var radioPlaybackEngine: Factory<any RadioPlaybackEngine> {
        self {
            #if canImport(UIKit) && !os(watchOS)
            AudioStreamingPlaybackEngine()
            #else
            StubRadioPlaybackEngine()
            #endif
        }
        .scope(.singleton)
        .onPreview { StubRadioPlaybackEngine() }
        .onTest { StubRadioPlaybackEngine() }
    }
}

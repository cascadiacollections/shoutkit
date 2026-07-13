import FactoryKit

public extension Container {
    /// The playback engine backing ``PlaybackController``, resolved via Factory
    /// instead of direct instantiation. Defaults to ``StubRadioPlaybackEngine``
    /// until a concrete engine registers itself as the production instance.
    /// `@MainActor` because `AudioOutput` (and therefore `RadioPlaybackEngine`) is.
    @MainActor
    var radioPlaybackEngine: Factory<any RadioPlaybackEngine> {
        self { StubRadioPlaybackEngine() }
            .scope(.singleton)
            .onPreview { StubRadioPlaybackEngine() }
            .onTest { StubRadioPlaybackEngine() }
    }
}

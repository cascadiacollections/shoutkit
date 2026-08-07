import FactoryKit

public extension Container {
    /// The playback engine backing ``PlaybackController``, resolved via Factory
    /// instead of direct instantiation.
    ///
    /// Defaults to ``StubRadioPlaybackEngine`` everywhere. The production
    /// AudioStreaming-backed engine lives in the separate, iOS-only
    /// `PlaybackEngineAudioStreaming` package and registers itself over this
    /// default via `registerProductionPlaybackEngine()`, called from
    /// `AppDependencies.bootstrap()` — that is what keeps this package free of
    /// the ogg/vorbis codec dependency AudioStreaming carries (#122).
    ///
    /// So a plain `Playback` consumer that never registers an engine gets
    /// silence rather than a build error, which is the right trade: the watch
    /// app already injects its own engine directly through
    /// `PlaybackController.init(output:)`, and previews and tests want the stub
    /// anyway. `@MainActor` because `AudioOutput` (and therefore
    /// ``RadioPlaybackEngine``) is.
    @MainActor
    var radioPlaybackEngine: Factory<any RadioPlaybackEngine> {
        self { StubRadioPlaybackEngine() }
            .scope(.singleton)
            .onPreview { StubRadioPlaybackEngine() }
            .onTest { StubRadioPlaybackEngine() }
    }
}

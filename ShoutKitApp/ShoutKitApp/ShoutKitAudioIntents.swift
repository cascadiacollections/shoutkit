import AppIntents
import Foundation
import OSLog

private let audioIntentsLogger = Logger(subsystem: "ShoutKit.App", category: "AudioIntents")

// MARK: - AppSchema.audio intents

/// The `.audio.playAudio` schema's `audioEntity` parameter accepts a fixed
/// menu of content kinds shared across every app that adopts it (songs,
/// albums, podcasts, live radio, …); a `@UnionValue` enum is how a single app
/// opts into just the cases it actually plays. ShoutKit only ever plays a
/// `StationEntity`.
@UnionValue
enum AudioItem {
    case liveRadioStation(StationEntity)
}

private extension AudioItem {
    var stationEntity: StationEntity {
        switch self {
        case let .liveRadioStation(entity):
            entity
        }
    }
}

/// AudioPlaybackIntent keeps this headless: Siri/Shortcuts start audio without
/// foregrounding the app (or demanding unlock), which is the whole point of
/// "Hey Siri, play KEXP on ShoutKit" while driving. Deep links use
/// StationLaunchRouter instead because opening the app is inherent to a URL
/// launch. This is the *explicit* path — the phrase always says "on
/// ShoutKit" — because `AppShortcutPhrase` can only bind plain
/// `AppEntity`/`AppEnum` parameters, and can't reference the schema's
/// union-typed `audioEntity` (see `PlayRadioAudioIntent` below for the
/// app-name-free path).
struct PlayStationIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Station"
    static let description = IntentDescription("Plays a radio station in ShoutKit.")

    @Parameter(title: "Station")
    var station: StationEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Reaches the same PlaybackController the app UI drives; bootstrap() is
        // idempotent, so this is safe even when the intent cold-launches the app.
        let services = AppDependencies.bootstrap()
        services.playbackController.play(station.station)
        return .result(dialog: "Playing \(station.name)")
    }
}

/// `@AppIntent(schema: .audio.warmupAudioQueue)` is Siri's pre-playback hook:
/// it resolves the target station's concrete stream endpoint, then asks
/// `StationConnectionPrewarmer` to warm that host's DNS/TCP/TLS path before the
/// later `playAudio` dispatch opens the real socket.
@AppIntent(schema: .audio.warmupAudioQueue)
struct WarmupRadioAudioQueueIntent {
    var audioEntity: AudioItem
    var playbackAttributes: Set<PlaybackAttributes>

    @MainActor
    func perform() async throws -> some ReturnsValue<WarmupAudioQueueResult> {
        let services = AppDependencies.bootstrap()
        let station = audioEntity.stationEntity
        do {
            let endpoint = try await services.directory.streamEndpoint(for: station.station)
            await services.stationConnectionPrewarmer.prewarm(streamURLs: [endpoint.url])
        } catch {
            let errorDescription = String(describing: error)
            audioIntentsLogger.error(
                """
                Failed to resolve Siri warmup endpoint for \
                \(station.name, privacy: .public): \(errorDescription, privacy: .private)
                """
            )
        }
        return .result(value: WarmupAudioQueueResult())
    }
}

/// `@AppIntent(schema: .audio.playAudio)` registers ShoutKit as a system
/// "play audio" handler for `StationEntity` content. Unlike `PlayStationIntent`
/// above, this one is never referenced by an `AppShortcut` phrase — its whole
/// purpose is passive registration, so the system's own "Play Audio" Siri
/// domain can dispatch a bare "play ⟨station⟩ radio" utterance straight to
/// `audioEntity`'s resolution (backed by `StationEntity`'s Spotlight index),
/// without the app name being spoken and without ShoutKit training a custom
/// phrase for it. `queueLocation`, `warmupAudioQueueResult`, and
/// `playbackAttributes` are schema-required bookkeeping for apps with a real
/// play queue; ShoutKit has none (station switches are immediate replacement,
/// not enqueueing), and the warmup hook prewarms the socket without needing any
/// payload from its result.
@AppIntent(schema: .audio.playAudio)
struct PlayRadioAudioIntent {
    static let title: LocalizedStringResource = "Play Radio"
    static let description = IntentDescription("Plays a radio station in ShoutKit.")

    var audioEntity: AudioItem
    var queueLocation: QueueInsertionLocation?
    var warmupAudioQueueResult: WarmupAudioQueueResult?
    var playbackAttributes: Set<PlaybackAttributes>

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let station = audioEntity.stationEntity
        // Reaches the same PlaybackController the app UI drives; bootstrap() is
        // idempotent, so this is safe even when the intent cold-launches the app.
        let services = AppDependencies.bootstrap()
        services.playbackController.play(station.station)
        return .result(dialog: "Playing \(station.name)")
    }
}

/// `.audio.playbackAttributes`: modifiers on how the audio plays (e.g. muted,
/// looping). ShoutKit's immediate single-station playback has none of these,
/// so the enum exists only to satisfy the schema — `perform()` always passes
/// an empty set.
@AppEnum(schema: .audio.playbackAttributes)
enum PlaybackAttributes: String {
    case none
    case shuffle
    case `repeat`

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .none: DisplayRepresentation(title: "None"),
        .shuffle: DisplayRepresentation(title: "Shuffle"),
        .repeat: DisplayRepresentation(title: "Repeat")
    ]
}

/// `.audio.queueInsertionLocation`: where in a play queue new audio should
/// land. ShoutKit has no queue — playing a station always replaces whatever
/// was playing — so `now` (immediate playback) is the only case that applies.
@AppEnum(schema: .audio.queueInsertionLocation)
enum QueueInsertionLocation: String {
    case now
    case next
    case tail

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .now: DisplayRepresentation(title: "Now"),
        .next: DisplayRepresentation(title: "Next"),
        .tail: DisplayRepresentation(title: "End of Queue")
    ]
}

/// `.audio.warmupAudioQueueResult`: marker value returned from
/// `WarmupRadioAudioQueueIntent`, which resolves and prewarms the target
/// station's stream host before Siri dispatches `PlayRadioAudioIntent`.
@AppEntity(schema: .audio.warmupAudioQueueResult)
struct WarmupAudioQueueResult: TransientAppEntity, Sendable {
    init() {}

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Ready")
    }
}

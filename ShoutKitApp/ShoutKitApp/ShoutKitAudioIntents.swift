import AppIntents
import CoreSpotlight
import Foundation
import OSLog
import RadioDirectory

private let audioIntentsLogger = Logger(subsystem: "ShoutKit.App", category: "AudioIntents")

// MARK: - AppSchema.audio intents (iOS 27+)

// Everything in this section is `@available(iOS 27, *)`. The `AppSchema.audio`
// macros generate conformances annotated iOS 27-only, so the types carrying them
// cannot build at the app's iOS 26 floor. They are gated rather than deleted
// because this is the app-name-free Siri route ("play KEXP radio", no "on
// ShoutKit") that the schema exists to provide — it simply activates only where
// the schema does. `PlayStationIntent` below is the ungated counterpart that
// works on every supported OS. See DECISIONS.md 2026-08-12.

/// The `.audio.playAudio` schema's `audioEntity` parameter accepts a fixed
/// menu of content kinds shared across every app that adopts it (songs,
/// albums, podcasts, live radio, …); a `@UnionValue` enum is how a single app
/// opts into just the cases it actually plays. ShoutKit only ever plays a
/// `LiveRadioStationEntity`.
@available(iOS 27, *)
@UnionValue
enum AudioItem {
    case liveRadioStation(LiveRadioStationEntity)
}

@available(iOS 27, *)
private extension AudioItem {
    var stationEntity: StationEntity {
        switch self {
        case let .liveRadioStation(entity):
            entity.stationEntity
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
@available(iOS 27, *)
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
/// "play audio" handler for radio content. Unlike `PlayStationIntent`
/// above, this one is never referenced by an `AppShortcut` phrase — its whole
/// purpose is passive registration, so the system's own "Play Audio" Siri
/// domain can dispatch a bare "play ⟨station⟩ radio" utterance straight to
/// `audioEntity`'s resolution (backed by `LiveRadioStationEntity`'s Spotlight
/// index — see `indexKnownStationsForSpotlight()`),
/// without the app name being spoken and without ShoutKit training a custom
/// phrase for it. `queueLocation`, `warmupAudioQueueResult`, and
/// `playbackAttributes` are schema-required bookkeeping for apps with a real
/// play queue; ShoutKit has none (station switches are immediate replacement,
/// not enqueueing), and the warmup hook prewarms the socket without needing any
/// payload from its result.
@available(iOS 27, *)
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
@available(iOS 27, *)
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
@available(iOS 27, *)
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
@available(iOS 27, *)
@AppEntity(schema: .audio.warmupAudioQueueResult)
struct WarmupAudioQueueResult: TransientAppEntity, Sendable {
    init() {}

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Ready")
    }
}

// MARK: - AppSchema.audio registration (iOS 27+)

/// The schema-conforming twin of ``StationEntity``.
///
/// `@AppEntity(schema: .audio.liveRadioStation)` is what registers ShoutKit as a
/// system *radio content provider*: with it, Siri can route a bare "play
/// ⟨station⟩ radio" utterance here on the strength of the schema alone, without
/// the app name being spoken. Plain `AppEntity` + `IndexedEntity` only lets Siri
/// look a station up *once it already knows to ask ShoutKit* (see DECISIONS.md,
/// 2026-07-15).
///
/// It exists as a separate type purely because the macro's generated conformance
/// is `@available(iOS 27, *)`, which ``StationEntity`` cannot be — that type is a
/// plain `@Parameter` on ``PlayStationIntent`` and has to build at the iOS 26
/// floor. So the two split the job: `StationEntity` carries the app-name-explicit
/// path that works everywhere, and this carries the app-name-free path that
/// activates on iOS 27. Both project the same `Station`, and this one converts
/// back through ``stationEntity`` so no playback code is duplicated.
@available(iOS 27, *)
@AppEntity(schema: .audio.liveRadioStation)
struct LiveRadioStationEntity: Sendable {
    static let defaultQuery = LiveRadioStationEntityQuery()

    let id: String
    let name: String
    let genre: String
    let artworkURLString: String?
    let streamURLString: String?

    /// The schema's canonical display name.
    var title: String { name }
    /// The network/broadcaster behind the stream (e.g. "NPR"). ShoutKit doesn't
    /// track this separately from the station itself.
    var providerName: String? { nil }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(genre)")
    }

    init(_ entity: StationEntity) {
        id = entity.id
        name = entity.name
        genre = entity.genre
        artworkURLString = entity.artworkURLString
        streamURLString = entity.streamURLString
    }

    /// Converts back to the ungated type so the intents can reuse the existing
    /// `Station` projection rather than duplicating it.
    var stationEntity: StationEntity {
        StationEntity(
            id: id,
            name: name,
            genre: genre,
            artworkURLString: artworkURLString,
            streamURLString: streamURLString
        )
    }

    var station: Station { stationEntity.station }
}

/// Delegates wholesale to ``StationEntityQuery`` and maps the result, so the
/// favorites/curated/recents/cache resolution order is defined in exactly one
/// place regardless of which entity type Siri asked for.
@available(iOS 27, *)
struct LiveRadioStationEntityQuery: EntityQuery, EntityStringQuery {
    private let base = StationEntityQuery()

    @MainActor
    func entities(for identifiers: [String]) async throws -> [LiveRadioStationEntity] {
        try await base.entities(for: identifiers).map(LiveRadioStationEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [LiveRadioStationEntity] {
        try await base.suggestedEntities().map(LiveRadioStationEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [LiveRadioStationEntity] {
        try await base.entities(matching: string).map(LiveRadioStationEntity.init)
    }
}

/// The schema entity needs its own index entry: the app-name-free "play
/// ⟨station⟩ radio" route resolves `audioEntity` against the index for *that*
/// type, so indexing only ``StationEntity`` would register the schema and then
/// give Siri nothing to match against.
@available(iOS 27, *)
extension LiveRadioStationEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        stationEntity.attributeSet
    }
}

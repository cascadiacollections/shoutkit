import AppIntents
import CoreSpotlight
import Foundation
import OSLog
import Persistence
import RadioDirectory
import SwiftData
import UniformTypeIdentifiers

private let shortcutsLogger = Logger(subsystem: "ShoutKit.App", category: "Shortcuts")

// MARK: - Station entity

/// A radio station as Siri/Shortcuts sees it. Carries the full snapshot needed to
/// play without a directory round-trip, mirroring how Persistence snapshots
/// stations for the same reason.
///
/// `@AppEntity(schema: .audio.liveRadioStation)` registers ShoutKit as a system
/// radio-content provider under `AppSchema.audio` (iOS 27+): Siri can route a
/// bare "play ⟨station⟩ radio" utterance here on the strength of the schema
/// alone, without the app name being spoken, unlike the plain `AppEntity`
/// conformance this replaces. Raising the deployment floor to iOS 27 for this
/// was previously deferred (see DECISIONS.md, 2026-07-06) — revisited here.
@AppEntity(schema: .audio.liveRadioStation)
struct StationEntity: Codable, Sendable {
    static let defaultQuery = StationEntityQuery()

    let id: String
    let name: String
    let genre: String
    let artworkURLString: String?
    let streamURLString: String?

    /// The schema's canonical display name (distinct from `name`, which the rest
    /// of the app/entity query code already uses).
    var title: String { name }
    /// The network/broadcaster behind the stream (e.g. "NPR"). ShoutKit doesn't
    /// track this separately from the station itself.
    var providerName: String? { nil }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(genre)")
    }

    init(station: Station) {
        id = station.id
        name = station.name
        genre = station.genre
        artworkURLString = station.artworkURL?.absoluteString
        streamURLString = station.preferredStreamURL?.absoluteString
    }

    var station: Station {
        Station(
            id: id,
            name: name,
            genre: genre,
            listenerCount: 0,
            artworkURL: artworkURLString.flatMap(URL.init(string:)),
            preferredStreamURL: streamURLString.flatMap(URL.init(string:))
        )
    }
}

// MARK: - Spotlight / semantic-index discoverability

/// Lets Siri and system search resolve a station by name/genre even before the
/// user has ever asked to play it by voice.
extension StationEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .audio)
        set.title = name
        set.contentDescription = genre
        set.keywords = [name, genre]
        return set
    }
}

// MARK: - Entity query

/// Resolves station entities from what the app already knows: curated stations,
/// SwiftData favorites/recents, and a small cache of stations previously surfaced
/// to Shortcuts (so a saved shortcut referencing a searched station still resolves
/// later — Shortcuts persists only the entity's id). Free-text matching goes to
/// the live directory.
struct StationEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        let known = knownStations()
        return identifiers.compactMap { id in known.first { $0.id == id } }
    }

    @MainActor
    func suggestedEntities() async throws -> [StationEntity] {
        Array(knownStations().prefix(10))
    }

    @MainActor
    func entities(matching string: String) async throws -> [StationEntity] {
        let services = AppDependencies.bootstrap()
        let stations = (try? await services.directory.searchStations(matching: string, limit: 10)) ?? []
        let entities = stations.map(StationEntity.init(station:))
        // Remember search results so a shortcut saved against one still resolves
        // by id after the search context is gone.
        IntentStationCache.remember(entities)
        return entities
    }

    /// Favorites first (most intentional), then curated, then recents, then the
    /// shortcut cache — deduplicated by id, order-preserving.
    @MainActor
    private func knownStations() -> [StationEntity] {
        let services = AppDependencies.bootstrap()
        let context = services.container.mainContext

        let favorites = (try? context.fetch(
            FetchDescriptor<FavoriteStation>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )) ?? []
        let recents = (try? context.fetch(
            FetchDescriptor<RecentStation>(sortBy: [SortDescriptor(\.playedAt, order: .reverse)])
        )) ?? []

        let candidates = favorites.map { StationEntity(station: $0.station) }
            + PreferredStations.all.map(StationEntity.init(station:))
            + recents.map { StationEntity(station: $0.station) }
            + IntentStationCache.load()

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }

    /// Pushes the currently known stations into Spotlight's semantic index so
    /// Siri can resolve "play ⟨station⟩" for a station from a previous
    /// session, not just ones searched or played this run. Called once at
    /// launch (`AppDependencies.bootstrap()`); a favorite toggled mid-session
    /// isn't re-indexed until the next launch — an accepted v1 gap, same
    /// category as the album-art lookup's "best effort" framing.
    @MainActor
    func indexKnownStationsForSpotlight() async {
        let entities = knownStations()
        guard entities.isEmpty == false else { return }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

/// UserDefaults-backed memory of stations previously handed to Shortcuts, so the
/// entity query can reconstruct them from a bare id.
enum IntentStationCache {
    private static let key = DefaultsKey<[StationEntity]>.codable("intents.station.cache", default: [])
    private static let capacity = 50

    static func load() -> [StationEntity] {
        UserDefaults.standard.value(for: key)
    }

    static func remember(_ entities: [StationEntity]) {
        guard entities.isEmpty == false else { return }

        var seen = Set<String>()
        let merged = (entities + load()).filter { seen.insert($0.id).inserted }
        let capped = Array(merged.prefix(capacity))

        UserDefaults.standard.set(capped, for: key)
    }
}

// MARK: - Intents

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
            shortcutsLogger.error(
                "Failed to resolve Siri warmup endpoint for \(station.name, privacy: .public): \(errorDescription, privacy: .private)"
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

struct OpenShoutKitIntent: AppIntent {
    static let title: LocalizedStringResource = "Open ShoutKit"
    static let description = IntentDescription("Opens ShoutKit.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// A read-only companion to `PlayStationIntent`/`PlayRadioAudioIntent`: reports
/// what's currently playing rather than starting playback, so it stays
/// headless like they do.
struct GetCurrentPlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Playing"
    static let description = IntentDescription("Reports which station is currently playing in ShoutKit.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppDependencies.bootstrap()
        guard let station = services.playbackController.currentStation else {
            return .result(dialog: "Nothing is playing right now.")
        }
        guard let track = services.playbackController.nowPlaying, let title = track.title else {
            return .result(dialog: "Playing \(station.name).")
        }
        let trackDescription = track.artist.map { "\(title) by \($0)" } ?? title
        return .result(dialog: "Playing \(trackDescription) on \(station.name).")
    }
}

/// Toggles the currently playing station's favorite state — "this" in "add
/// this to my favorites" is implicitly whatever ShoutKit is playing, mirroring
/// the heart button on `StationRow`. There's no station parameter to resolve:
/// unlike `PlayStationIntent`, there's nothing to name by voice here.
struct ToggleFavoriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Favorite"
    static let description = IntentDescription(
        "Adds or removes the currently playing station from your ShoutKit favorites."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppDependencies.bootstrap()
        guard let station = services.playbackController.currentStation else {
            return .result(dialog: "Nothing is playing right now.")
        }
        let isFavoriteNow = services.libraryStore.toggleFavorite(station)
        return .result(
            dialog: isFavoriteNow
                ? "Added \(station.name) to your favorites."
                : "Removed \(station.name) from your favorites."
        )
    }
}

// MARK: - App Shortcuts

struct ShoutKitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayStationIntent(),
            phrases: [
                "Play \(\.$station) on \(.applicationName)",
                "Listen to \(\.$station) on \(.applicationName)"
            ],
            shortTitle: "Play Station",
            systemImageName: "play.circle"
        )

        AppShortcut(
            intent: OpenShoutKitIntent(),
            phrases: [
                "Open \(.applicationName)"
            ],
            shortTitle: "Open",
            systemImageName: "dot.radiowaves.left.and.right"
        )

        AppShortcut(
            intent: GetCurrentPlaybackIntent(),
            phrases: [
                "What's playing on \(.applicationName)",
                "What is playing on \(.applicationName)"
            ],
            shortTitle: "What's Playing",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: ToggleFavoriteIntent(),
            phrases: [
                "Add this station to my favorites in \(.applicationName)",
                "Favorite this station in \(.applicationName)"
            ],
            shortTitle: "Toggle Favorite",
            systemImageName: "heart"
        )
    }
}

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
    private static let logger = Logger(subsystem: "ShoutKit.App", category: "StationEntityQuery")

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
    /// category as the album-art lookup's "best effort" framing. Refresh the
    /// App Shortcut parameter cache afterward so Shortcuts search and Siri see
    /// the same station set the Spotlight index just received.
    @MainActor
    func indexKnownStationsForSpotlight() async {
        let entities = knownStations()
        if entities.isEmpty == false {
            do {
                try await CSSearchableIndex.default().indexAppEntities(entities)
            } catch {
                Self.logger.error("Failed to index Siri stations in Spotlight: \(error, privacy: .public)")
            }
        }
        ShoutKitShortcuts.updateAppShortcutParameters()
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

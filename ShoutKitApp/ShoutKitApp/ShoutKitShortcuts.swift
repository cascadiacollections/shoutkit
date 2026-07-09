import AppIntents
import Foundation
import Persistence
import RadioDirectory
import SwiftData

// MARK: - Station entity

/// A radio station as Siri/Shortcuts sees it. Carries the full snapshot needed to
/// play without a directory round-trip, mirroring how Persistence snapshots
/// stations for the same reason.
struct StationEntity: AppEntity, Codable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Radio Station"
    static let defaultQuery = StationEntityQuery()

    let id: String
    let name: String
    let genre: String
    let artworkURLString: String?
    let streamURLString: String?

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
}

/// UserDefaults-backed memory of stations previously handed to Shortcuts, so the
/// entity query can reconstruct them from a bare id.
enum IntentStationCache {
    private static let key = "intents.station.cache"
    private static let capacity = 50

    static func load() -> [StationEntity] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entities = try? JSONDecoder().decode([StationEntity].self, from: data) else {
            return []
        }
        return entities
    }

    static func remember(_ entities: [StationEntity]) {
        guard entities.isEmpty == false else { return }

        var seen = Set<String>()
        let merged = (entities + load()).filter { seen.insert($0.id).inserted }
        let capped = Array(merged.prefix(capacity))

        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Intents

/// AudioPlaybackIntent keeps this headless: Siri/Shortcuts start audio without
/// foregrounding the app (or demanding unlock), which is the whole point of
/// "Hey Siri, play KEXP" while driving. Deep links use StationLaunchRouter
/// instead because opening the app is inherent to a URL launch.
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

struct OpenShoutKitIntent: AppIntent {
    static let title: LocalizedStringResource = "Open ShoutKit"
    static let description = IntentDescription("Opens ShoutKit.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
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
    }
}

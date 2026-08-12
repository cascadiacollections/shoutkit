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
/// Deliberately a **plain** `AppEntity`, not `@AppEntity(schema: .audio.…)`.
/// The schema macro's generated conformance is `@available(iOS 27, *)` on the
/// type itself, and this type must build at the iOS 26 floor: it is a plain
/// `@Parameter` on ``PlayStationIntent``, which backs the `AppShortcut` phrases
/// and is reached from `AppDependencies.bootstrap()`. Marking it iOS 27-only
/// cascades through all of that.
///
/// The schema conformance lives on ``LiveRadioStationEntity`` below instead —
/// see the comment there for how the two divide the work.
struct StationEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Station")
    static let defaultQuery = StationEntityQuery()

    let id: String
    let name: String
    let genre: String
    let artworkURLString: String?
    let streamURLString: String?

    /// The schema's canonical display name (distinct from `name`, which the rest
    /// of the app/entity query code already uses). Kept here as well as on
    /// ``LiveRadioStationEntity`` so the two stay trivially convertible.
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

    fileprivate init(
        id: String,
        name: String,
        genre: String,
        artworkURLString: String?,
        streamURLString: String?
    ) {
        self.id = id
        self.name = name
        self.genre = genre
        self.artworkURLString = artworkURLString
        self.streamURLString = streamURLString
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
        let knownByID = Dictionary(uniqueKeysWithValues: knownStations().map { ($0.id, $0) })
        let services = AppDependencies.bootstrap()

        var resolved: [StationEntity] = []
        resolved.reserveCapacity(identifiers.count)

        for id in identifiers {
            if let known = knownByID[id] {
                resolved.append(known)
                continue
            }

            // Best effort: unresolved IDs are skipped so one directory failure
            // doesn't block other valid entities in the same request.
            guard let station = try? await services.directory.station(id: id) else { continue }
            let fallback = StationEntity(station: station)
            IntentStationCache.remember([fallback])
            resolved.append(fallback)
        }

        return resolved
    }

    @MainActor
    func suggestedEntities() async throws -> [StationEntity] {
        Array(knownStations().prefix(10))
    }

    @MainActor
    func entities(matching string: String) async throws -> [StationEntity] {
        let services = AppDependencies.bootstrap()
        // Best effort: returning an empty suggestion list is preferable to
        // failing the Shortcuts picker for transient network errors.
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

        // Best effort: shortcuts can still resolve curated/cache stations when a
        // store read fails.
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

            // Separate call rather than one combined index: `indexAppEntities`
            // is generic over a single entity type, and the schema type only
            // exists on iOS 27. A failure here costs the app-name-free route
            // only — the explicit "on ShoutKit" phrases still resolve from the
            // index above — so it is logged and swallowed like its sibling.
            if #available(iOS 27, *) {
                do {
                    try await CSSearchableIndex.default()
                        .indexAppEntities(entities.map(LiveRadioStationEntity.init))
                } catch {
                    Self.logger.error(
                        "Failed to index Siri radio-schema stations in Spotlight: \(error, privacy: .public)"
                    )
                }
            }
        }
        ShoutKitShortcuts.updateAppShortcutParameters()
    }
}

/// UserDefaults-backed memory of stations previously handed to Shortcuts, so the
/// entity query can reconstruct them from a bare id.
enum IntentStationCache {
    private struct CachedStation: Codable, Sendable {
        let id: String
        let name: String
        let genre: String
        let artworkURLString: String?
        let streamURLString: String?

        init(entity: StationEntity) {
            id = entity.id
            name = entity.name
            genre = entity.genre
            artworkURLString = entity.artworkURLString
            streamURLString = entity.streamURLString
        }

        var entity: StationEntity {
            StationEntity(
                id: id,
                name: name,
                genre: genre,
                artworkURLString: artworkURLString,
                streamURLString: streamURLString
            )
        }
    }

    private static let key = DefaultsKey<[CachedStation]>.codable("intents.station.cache", default: [])
    private static let capacity = 50

    static func load(defaults: UserDefaults = .standard) -> [StationEntity] {
        defaults.value(for: key).map(\.entity)
    }

    static func remember(_ entities: [StationEntity], defaults: UserDefaults = .standard) {
        guard entities.isEmpty == false else { return }

        var seen = Set<String>()
        let merged = (entities + load(defaults: defaults)).filter { seen.insert($0.id).inserted }
        let capped = Array(merged.prefix(capacity)).map(CachedStation.init(entity:))

        defaults.set(capped, for: key)
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
        // Mirror the change into the quick-play widget snapshot. This intent
        // runs headless (`openAppWhenRun == false`) — from Siri or a CarPlay
        // session no RootView exists, so its favorites observer (the usual
        // publisher) never fires and the widget would keep showing, and
        // deep-linking to, the stale list until the next full UI launch.
        QuickPlayWidgetPublisher.publish(services.libraryStore.orderedFavorites())
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

import AppIntents
import NowPlayingActivityCore
import SwiftUI
import WidgetKit

// MARK: - Configuration entity

/// A favorite station as the widget's configuration picker sees it. Backed by the
/// App Group snapshot the app writes, so the picker (and the timeline) resolve
/// without touching the app's dependency graph.
struct FavoriteStationAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Favorite Station")
    static let defaultQuery = FavoriteStationQuery()

    let id: String
    let name: String
    let genre: String

    var displayRepresentation: DisplayRepresentation {
        genre.isEmpty
            ? DisplayRepresentation(title: "\(name)")
            : DisplayRepresentation(title: "\(name)", subtitle: "\(genre)")
    }

    init(snapshot: QuickPlayStationSnapshot) {
        id = snapshot.id
        name = snapshot.name
        genre = snapshot.genre
    }
}

struct FavoriteStationQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FavoriteStationAppEntity] {
        let known = QuickPlayFavoritesStore.load()
        return identifiers.compactMap { id in
            known.first { $0.id == id }.map(FavoriteStationAppEntity.init(snapshot:))
        }
    }

    func suggestedEntities() async throws -> [FavoriteStationAppEntity] {
        QuickPlayFavoritesStore.load().map(FavoriteStationAppEntity.init(snapshot:))
    }
}

// MARK: - Configuration intent

/// The widget's edit-mode configuration: which favorite the tile plays. Leaving
/// it unset falls back to the user's first favorite (see `QuickPlayProvider`).
struct SelectFavoriteStationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Station"
    static let description = IntentDescription("Pick a favorite station to play with one tap.")

    @Parameter(title: "Station")
    var station: FavoriteStationAppEntity?
}

// MARK: - Timeline

struct QuickPlayEntry: TimelineEntry {
    let date: Date
    let station: QuickPlayStationSnapshot?
}

struct QuickPlayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickPlayEntry {
        QuickPlayEntry(date: .now, station: QuickPlayFavoritesStore.load().first)
    }

    func snapshot(for configuration: SelectFavoriteStationIntent, in context: Context) async -> QuickPlayEntry {
        QuickPlayEntry(date: .now, station: resolved(configuration))
    }

    func timeline(
        for configuration: SelectFavoriteStationIntent,
        in context: Context
    ) async -> Timeline<QuickPlayEntry> {
        // Favorites change rarely, and the app reloads this timeline on every
        // change, so a single never-expiring entry is all that's needed.
        Timeline(entries: [QuickPlayEntry(date: .now, station: resolved(configuration))], policy: .never)
    }

    /// The user's chosen station, falling back to their first favorite so a
    /// freshly added widget still shows something before it's configured.
    private func resolved(_ configuration: SelectFavoriteStationIntent) -> QuickPlayStationSnapshot? {
        let favorites = QuickPlayFavoritesStore.load()
        if let id = configuration.station?.id, let match = favorites.first(where: { $0.id == id }) {
            return match
        }
        return favorites.first
    }
}

// MARK: - View

struct QuickPlayWidgetEntryView: View {
    let entry: QuickPlayEntry

    var body: some View {
        Group {
            if let station = entry.station {
                stationView(station)
            } else {
                emptyView
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func stationView(_ station: QuickPlayStationSnapshot) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.tint)

            Spacer(minLength: 0)

            Text(station.name)
                .font(.headline)
                .lineLimit(2)

            if station.genre.isEmpty == false {
                Text(station.genre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Label("Play", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        // Tapping the tile opens the app on the station with autoPlay set, the
        // same deep link Shortcuts and notifications use.
        if let url = URL(string: station.deepLinkURLString) {
            content.widgetURL(url)
        } else {
            content
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Add a favorite in ShoutKit to play it from here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget

struct QuickPlayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: QuickPlayFavoritesStore.widgetKind,
            intent: SelectFavoriteStationIntent.self,
            provider: QuickPlayProvider()
        ) { entry in
            QuickPlayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Quick Play")
        .description("Tap to play a favorite station.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

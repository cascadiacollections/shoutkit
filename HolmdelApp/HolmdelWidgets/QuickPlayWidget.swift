import AppIntents
import NowPlayingActivityCore
import SwiftUI
import UIKit
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
    /// Set while a station is playing or paused (and, when the widget is
    /// configured, only if it's the configured station). Takes over the tile.
    var nowPlaying: NowPlayingWidgetSnapshot?
}

struct QuickPlayProvider: AppIntentTimelineProvider {
    /// How often a widget showing a live station re-checks the snapshot on its
    /// own: a backstop for a reload request the system declined (the app asks on
    /// every change while playing; see `NowPlayingWidgetReloadPolicy`).
    /// Widget-initiated refreshes are paced by the system.
    private static let liveRefreshInterval: TimeInterval = 15 * 60

    func placeholder(in _: Context) -> QuickPlayEntry {
        QuickPlayEntry(date: .now, station: QuickPlayFavoritesStore.load().first)
    }

    func snapshot(for configuration: SelectFavoriteStationIntent, in _: Context) async -> QuickPlayEntry {
        entry(for: configuration, at: .now)
    }

    func timeline(
        for configuration: SelectFavoriteStationIntent,
        in _: Context,
    ) async -> Timeline<QuickPlayEntry> {
        let now = Date.now
        let current = entry(for: configuration, at: now)
        guard let nowPlaying = current.nowPlaying else {
            // Favorites change rarely, and the app reloads this timeline on every
            // change (and on every play/stop), so one entry is all that's needed.
            return Timeline(entries: [current], policy: .never)
        }
        // If the app dies without writing `.stopped`, drop back to the quick-play
        // tile once the snapshot expires instead of showing a dead station as live.
        let fallback = QuickPlayEntry(date: nowPlaying.expiresAt, station: current.station)
        return Timeline(
            entries: [current, fallback],
            policy: .after(now.addingTimeInterval(Self.liveRefreshInterval)),
        )
    }

    private func entry(for configuration: SelectFavoriteStationIntent, at date: Date) -> QuickPlayEntry {
        QuickPlayEntry(
            date: date,
            station: resolved(configuration),
            nowPlaying: nowPlaying(for: configuration, at: date),
        )
    }

    /// The live snapshot if this widget should show it: any station when the
    /// widget isn't configured, otherwise only the configured one.
    private func nowPlaying(
        for configuration: SelectFavoriteStationIntent,
        at date: Date,
    ) -> NowPlayingWidgetSnapshot? {
        guard let snapshot = NowPlayingWidgetStore.load(), snapshot.isShowable(at: date) else { return nil }
        if let configuredID = configuration.station?.id, configuredID != snapshot.stationID {
            return nil
        }
        return snapshot
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
            if let nowPlaying = entry.nowPlaying {
                NowPlayingTileView(snapshot: nowPlaying)
            } else if let station = entry.station {
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
            Text("Add a favorite in Holmdel to play it from here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Now playing

/// The tile while a station is loaded: its artwork (album art, else the
/// station's own, else the radio glyph), the station, and the live track.
struct NowPlayingTileView: View {
    let snapshot: NowPlayingWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let content = Group {
            if family == .systemMedium {
                HStack(spacing: 12) {
                    artwork
                        .frame(maxHeight: .infinity)
                    details
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    artwork
                        .frame(width: 56, height: 56)
                    Spacer(minLength: 0)
                    details
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        // Same link the quick-play tile uses: opens Now Playing, and resumes a
        // paused stream without reconnecting a live one.
        if let url = URL(string: snapshot.deepLinkURLString) {
            content.widgetURL(url)
        } else {
            content
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let token = snapshot.artworkToken,
           let url = NowPlayingWidgetStore.artworkFileURL(forToken: token),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                // Tinted and clear Home Screens (iOS 26) and the macOS desktop's
                // monochrome style draw images as a silhouette by default, and a
                // square cover's silhouette is a blank tile. Keep artwork in color.
                .widgetAccentedRenderingMode(.fullColor)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .accessibilityHidden(true)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(
                snapshot.status == .paused ? LocalizedStringKey("Paused") : LocalizedStringKey("Now Playing"),
                systemImage: snapshot.status == .paused ? "pause.fill" : "waveform",
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tint)
            .lineLimit(1)

            Text(snapshot.stationName)
                .font(.headline)
                .lineLimit(family == .systemMedium ? 2 : 1)

            if let title = snapshot.trackTitle {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            if let artist = snapshot.artist {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct QuickPlayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: QuickPlayFavoritesStore.widgetKind,
            intent: SelectFavoriteStationIntent.self,
            provider: QuickPlayProvider(),
        ) { entry in
            QuickPlayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Quick Play")
        .description("Tap to play a favorite station, and see what's playing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

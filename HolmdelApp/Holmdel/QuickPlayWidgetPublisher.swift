import Foundation
import NowPlayingActivityCore
import Persistence
import RadioDirectory
import WidgetKit

/// Mirrors the user's favorites into the App Group snapshot the Home Screen
/// quick-play widget reads, then asks WidgetKit to reload the widget's timeline.
///
/// The widget extension can't reach the app's SwiftData store or dependency
/// graph, so the app is the only place that can turn a `FavoriteStation` into the
/// display fields plus a ready-to-open `holmdel://station?...` deep link. Called
/// at launch and whenever the favorites list changes.
@MainActor
enum QuickPlayWidgetPublisher {
    /// Upper bound on how many favorites are published. The widget only ever
    /// surfaces one at a time; its configuration picker doesn't need an unbounded
    /// history.
    private static let capacity = 50

    static func publish(_ favorites: [FavoriteStation]) {
        publishStations(favorites.prefix(capacity).map(\.station))
    }

    static func publishStations(_ stations: [Station]) {
        let snapshots = stations.prefix(capacity).map { station -> QuickPlayStationSnapshot in
            let link = StationLink(station: station, autoPlay: true, presentNowPlaying: true)
            return QuickPlayStationSnapshot(
                id: station.id,
                name: station.name,
                genre: station.genre,
                deepLinkURLString: link.url().absoluteString
            )
        }

        QuickPlayFavoritesStore.save(Array(snapshots))
        WidgetCenter.shared.reloadTimelines(ofKind: QuickPlayFavoritesStore.widgetKind)
    }
}

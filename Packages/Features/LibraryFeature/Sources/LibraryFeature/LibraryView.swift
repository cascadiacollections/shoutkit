import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SwiftData
import SwiftUI

/// The Favorites tab: favorited stations plus a recently played section, backed by
/// SwiftData. Rows play through the shared playback controller.
public struct LibraryView: View {
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FavoriteStation.createdAt, order: .reverse)
    private var favorites: [FavoriteStation]

    @Query(sort: \RecentStation.playedAt, order: .reverse)
    private var recents: [RecentStation]

    public init() {}

    public var body: some View {
        Group {
            if favorites.isEmpty && recents.isEmpty {
                emptyState
            } else {
                List {
                    if favorites.isEmpty == false {
                        Section("Favorites") {
                            ForEach(favorites) { favorite in
                                row(for: favorite.station)
                            }
                            .onDelete(perform: deleteFavorites)
                        }
                    }

                    if recents.isEmpty == false {
                        Section("Recently Played") {
                            ForEach(recents.prefix(15)) { recent in
                                row(for: recent.station)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color.shoutKitBackground)
    }

    private func row(for station: Station) -> some View {
        StationRow(
            station: station,
            phase: playback?.phase(for: station) ?? .idle,
            isFavorite: library?.isFavorite(station) ?? false,
            onTap: { playback?.toggle(station) },
            onToggleFavorite: library.map { store in { store.toggleFavorite(station) } }
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Favorites Yet", systemImage: "heart")
        } description: {
            Text("Stations you favorite and recently play will appear here.")
        }
    }

    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            let favorite = favorites[index]
            library?.removeFavorite(stationID: favorite.stationID)
        }
    }
}

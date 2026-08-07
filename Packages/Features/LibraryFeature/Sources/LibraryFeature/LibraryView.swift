import DesignSystem
import LibraryFeatureCore
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
    @Environment(\.openURL) private var openURL

    @Query(sort: \FavoriteStation.sortIndex, order: .forward)
    private var favorites: [FavoriteStation]

    @Query(sort: \RecentStation.playedAt, order: .reverse)
    private var recents: [RecentStation]

    @Query(sort: \RecentlyHeardTrack.heardAt, order: .reverse)
    private var recentlyHeardTracks: [RecentlyHeardTrack]

    public init() {}

    public var body: some View {
        Group {
            if favorites.isEmpty && recents.isEmpty && recentlyHeardTracks.isEmpty {
                emptyState
            } else {
                List {
                    if favorites.isEmpty == false {
                        Section("Favorites") {
                            ForEach(favorites) { favorite in
                                row(for: favorite.station)
                            }
                            .onDelete(perform: deleteFavorites)
                            .onMove(perform: moveFavorites)
                        }
                    }

                    if recents.isEmpty == false {
                        Section("Recently Played") {
                            ForEach(recents.prefix(15)) { recent in
                                row(for: recent.station)
                            }
                            .onDelete(perform: deleteRecents)
                        }
                    }

                    if recentlyHeardTracks.isEmpty == false {
                        Section("Recently Heard") {
                            ForEach(recentlyHeardTracks) { track in
                                recentlyHeardRow(for: track)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .toolbar {
                    if favorites.isEmpty == false || recents.isEmpty == false {
                        ToolbarItem(placement: .topBarTrailing) {
                            EditButton()
                        }
                    }
                }
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
            Text("Favorites, recently played stations, and recently heard tracks appear here.")
        }
    }

    private func recentlyHeardRow(for track: RecentlyHeardTrack) -> some View {
        let appleMusicURL = track.appleMusicURLString.flatMap(URL.init(string:))
        let content = recentlyHeardRowContent(
            for: track,
            isLinked: appleMusicURL != nil
        )
        return Group {
            if let url = appleMusicURL {
                Button {
                    openURL(url)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private func recentlyHeardRowContent(for track: RecentlyHeardTrack, isLinked: Bool) -> some View {
        VStack(alignment: .leading, spacing: ShoutKitSpacing.extraSmall) {
            Text(track.title ?? "Unknown Track")
                .font(.headline)
            Text(track.artist ?? "Unknown Artist")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text(track.stationName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(track.heardAt, style: .relative)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if isLinked {
                    Image(systemName: "apple.logo")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func deleteRecents(at offsets: IndexSet) {
        let stationIDs = LibraryListEditing.stationIDsForRecentDeletion(
            recentStationIDsNewestFirst: recents.map(\.stationID),
            offsets: offsets
        )
        for stationID in stationIDs {
            library?.removeRecent(stationID: stationID)
        }
    }

    private func deleteFavorites(at offsets: IndexSet) {
        let stationIDs = LibraryListEditing.stationIDsForFavoriteDeletion(
            favoriteStationIDs: favorites.map(\.stationID),
            offsets: offsets
        )
        for stationID in stationIDs {
            library?.removeFavorite(stationID: stationID)
        }
    }

    private func moveFavorites(from source: IndexSet, to destination: Int) {
        library?.moveFavorites(favorites, from: source, to: destination)
    }
}

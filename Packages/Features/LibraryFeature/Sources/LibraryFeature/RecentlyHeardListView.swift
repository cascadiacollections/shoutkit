import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// The full track history, pushed from the Favorites tab's "Recently Heard" row.
///
/// This used to be a fourth section stacked under Favorites, Recently Played and
/// Top Tracks — an unbounded list of every track the app has ever seen, below
/// three bounded ones. It made the pane's length a function of how long the app
/// had been used, and buried the sections above it on any well-used install.
/// Top Tracks is the summary; this is the drill-in behind it.
struct RecentlyHeardListView: View {
    @Environment(\.openURL) private var openURL

    @Query(sort: \RecentlyHeardTrack.heardAt, order: .reverse)
    private var tracks: [RecentlyHeardTrack]

    var body: some View {
        List {
            ForEach(tracks) { track in
                row(for: track)
            }
        }
        .listStyle(.insetGrouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(String(localized: "Recently Heard", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Tracks Yet", bundle: .module),
                    systemImage: "music.note.list",
                    description: Text(
                        String(localized: "Tracks you hear while listening appear here.", bundle: .module)
                    )
                )
            }
        }
    }

    private func row(for track: RecentlyHeardTrack) -> some View {
        let appleMusicURL = track.appleMusicURLString.flatMap(URL.init(string:))
        let content = rowContent(for: track, isLinked: appleMusicURL != nil)
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

    private func rowContent(for track: RecentlyHeardTrack, isLinked: Bool) -> some View {
        VStack(alignment: .leading, spacing: ShoutKitSpacing.extraSmall) {
            Text(track.title ?? String(localized: "Unknown Track", bundle: .module))
                .font(.headline)
            Text(track.artist ?? String(localized: "Unknown Artist", bundle: .module))
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
}

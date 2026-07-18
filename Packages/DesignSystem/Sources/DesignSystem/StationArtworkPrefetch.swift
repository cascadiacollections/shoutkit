import RadioDirectory
import SwiftUI

public extension View {
    /// Prefetches artwork for the stations just past `index` in a lazy station
    /// list, so their thumbnails are decoded (or in flight) by the time they
    /// scroll into view. Attach to each row; the overlapping look-ahead windows
    /// are deduplicated by `ArtworkThumbnailLoader`, so repeated calls are cheap.
    ///
    /// `displayScale` comes from `@Environment(\.displayScale)` at the call site
    /// so the prefetched decode size matches what `StationRow` requests exactly,
    /// keeping both on the same cache key.
    func prefetchStationArtwork(
        after index: Int,
        in stations: [Station],
        lookahead: Int = 6,
        displayScale: CGFloat
    ) -> some View {
        onAppear {
            let start = index + 1
            let end = min(start + lookahead, stations.count)
            guard start < end else { return }

            ArtworkThumbnailLoader.prefetch(
                stations[start..<end].map(\.artworkURL),
                maxPixelSize: StationArtworkView.listPixelSize(displayScale: displayScale)
            )
        }
    }
}

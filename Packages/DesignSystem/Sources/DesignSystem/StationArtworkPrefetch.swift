import RadioDirectory
import SwiftUI

public extension View {
    /// Prefetches artwork for the stations just past `index` in a lazy station
    /// list, so their thumbnails are decoded (or in flight) by the time they
    /// scroll into view. Attach to each row; the overlapping look-ahead windows
    /// are deduplicated by `ArtworkThumbnailLoader`, so repeated calls are cheap.
    ///
    /// `displayScale` comes from `@Environment(\.displayScale)` at the call site
    /// so the prefetched decode size matches what the row or tile requests
    /// exactly, keeping both on the same cache key.
    ///
    /// `maxPixelSize` must match the size the visible view will ask for. A
    /// prefetch at the wrong size is worse than none: it warms a cache entry
    /// nothing reads, then the view decodes the image a second time anyway.
    /// Pass `StationArtworkView.posterPixelSize` from a poster grid.
    func prefetchStationArtwork(
        after index: Int,
        in stations: [Station],
        lookahead: Int = 6,
        displayScale: CGFloat,
        maxPixelSize: CGFloat? = nil
    ) -> some View {
        onAppear {
            let start = index + 1
            let end = min(start + lookahead, stations.count)
            guard start < end else { return }

            ArtworkThumbnailLoader.prefetch(
                stations[start..<end].map(\.artworkURL),
                maxPixelSize: maxPixelSize
                    ?? StationArtworkView.listPixelSize(displayScale: displayScale)
            )
        }
    }
}

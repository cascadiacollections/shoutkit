import Playback
import RadioDirectory
import SwiftUI

/// A horizontal shelf of ``StationCard``s.
///
/// The place for a short, personal, *ordered* list — Recently Played — sitting
/// above a vertical grid of a longer one. Distinguishing the two by axis keeps
/// a single visual language (poster tiles everywhere) where using a different
/// component for each meant a full-width card floating above a card-less grid.
///
/// This is not the carousel the 2026-09-03 pass removed. That one held the head
/// of the *same* list the grid below it continued, which is what made it a
/// second shape for one thing.
public struct StationCarousel: View {
    private let stations: [Station]
    private let phase: (Station) -> StationPlaybackPhase
    private let isFavorite: (Station) -> Bool
    private let onTap: (Station) -> Void
    private let onToggleFavorite: ((Station) -> Void)?
    private let removeAction: ((Station) -> StationRowAction)?

    public init(
        stations: [Station],
        phase: @escaping (Station) -> StationPlaybackPhase,
        isFavorite: @escaping (Station) -> Bool = { _ in false },
        onTap: @escaping (Station) -> Void,
        onToggleFavorite: ((Station) -> Void)? = nil,
        removeAction: ((Station) -> StationRowAction)? = nil
    ) {
        self.stations = stations
        self.phase = phase
        self.isFavorite = isFavorite
        self.onTap = onTap
        self.onToggleFavorite = onToggleFavorite
        self.removeAction = removeAction
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: ShoutKitSpacing.medium) {
                ForEach(stations) { station in
                    // The fixed-width initializer: a shelf card's width is what
                    // makes the next one peek in from the trailing edge, so it
                    // can't be left to the container the way a grid tile's is.
                    StationCard(
                        station: station,
                        phase: phase(station),
                        width: 150,
                        isFavorite: isFavorite(station),
                        onTap: { onTap(station) },
                        onToggleFavorite: onToggleFavorite.map { toggle in { toggle(station) } },
                        removeAction: removeAction?(station)
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
        }
        // The shelf scrolls edge to edge; its content keeps the screen's
        // margins via the caller's padding, which a clipped ScrollView would
        // otherwise cut the peeking card off at.
        .scrollClipDisabled()
    }
}

#Preview {
    StationCarousel(
        stations: PreviewRadioDirectory.sampleStations,
        phase: { _ in .idle },
        onTap: { _ in }
    )
    .padding()
    .tint(.shoutKitAccent)
}

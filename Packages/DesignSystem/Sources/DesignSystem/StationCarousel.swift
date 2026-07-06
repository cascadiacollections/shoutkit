import Playback
import RadioDirectory
import SwiftUI

/// A horizontal carousel of ``StationCard``s used by discovery surfaces.
public struct StationCarousel: View {
    private let stations: [Station]
    private let phase: (Station) -> StationPlaybackPhase
    private let onTap: (Station) -> Void

    public init(
        stations: [Station],
        phase: @escaping (Station) -> StationPlaybackPhase,
        onTap: @escaping (Station) -> Void
    ) {
        self.stations = stations
        self.phase = phase
        self.onTap = onTap
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: ShoutKitSpacing.medium) {
                ForEach(stations) { station in
                    StationCard(
                        station: station,
                        phase: phase(station),
                        onTap: { onTap(station) }
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
        }
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

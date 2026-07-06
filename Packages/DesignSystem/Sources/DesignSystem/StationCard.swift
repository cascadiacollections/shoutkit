import Playback
import RadioDirectory
import SwiftUI

/// A poster-style station card for horizontal discovery carousels.
public struct StationCard: View {
    private let station: Station
    private let phase: StationPlaybackPhase
    private let width: CGFloat
    private let onTap: () -> Void

    public init(
        station: Station,
        phase: StationPlaybackPhase,
        width: CGFloat = 150,
        onTap: @escaping () -> Void
    ) {
        self.station = station
        self.phase = phase
        self.width = width
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
                StationArtworkView(
                    artworkURL: station.artworkURL,
                    size: width,
                    cornerRadius: ShoutKitRadius.card,
                    isPlaying: phase == .playing
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(station.name)
                        .font(.shoutKitCardTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(station.name), \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        if station.listenerCount > 0 {
            return "\(station.listenerCount.formatted()) listeners"
        }
        if let bitrate = station.bitrate {
            return "\(station.genre) · \(bitrate) kbps"
        }
        return station.genre
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: ShoutKitSpacing.medium) {
            ForEach(PreviewRadioDirectory.sampleStations) { station in
                StationCard(station: station, phase: .idle, onTap: {})
            }
        }
        .padding()
    }
    .tint(.shoutKitAccent)
}

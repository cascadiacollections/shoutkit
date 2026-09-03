import SwiftUI

/// The backdrop shown when a station has no usable artwork — and behind logos
/// too small to fill their tile.
///
/// Replaces a tinted rectangle with one generic radio glyph, which made every
/// artwork-less station look like every other one. A directory of a few thousand
/// community stations has a *lot* of these, so a grid of them was a grid of the
/// same square repeated. The gradient and monogram are derived from the station's
/// own name, so each one is recognisably itself and stays that way between
/// launches.
public struct ArtworkPlaceholder: View {
    private let monogram: String
    private let hue: Double

    public init(seed: String) {
        monogram = Self.monogram(for: seed)
        hue = Self.hue(for: seed)
    }

    public var body: some View {
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.52, brightness: 0.62),
                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.62, brightness: 0.40)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            // Sized to the tile rather than to a font metric: this stands in for
            // artwork, and artwork fills its frame at every Dynamic Type size.
            GeometryReader { proxy in
                Text(monogram)
                    .font(.system(size: proxy.size.width * 0.34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        // The station name is already announced by the row or tile that owns
        // this; a monogram of it read out again is noise.
        .accessibilityHidden(true)
    }

    /// One or two letters, the way a contact card derives initials: the first
    /// letter of each of the first two words, or the first two letters when
    /// there is only one word. Digits count — a lot of stations are called
    /// things like "90.3" — but punctuation and emoji do not.
    static func monogram(for seed: String) -> String {
        let words = seed
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .map { $0.filter { $0.isLetter || $0.isNumber } }
            .filter { $0.isEmpty == false }

        guard let first = words.first else { return "?" }
        if words.count >= 2, let second = words.dropFirst().first {
            return (first.prefix(1) + second.prefix(1)).uppercased()
        }
        return first.prefix(2).uppercased()
    }

    /// A stable hue in `0..<1`.
    ///
    /// FNV-1a rather than `Hashable`: Swift seeds `Hasher` per process, so the
    /// same station would pick a different colour on every launch — the one
    /// thing a generated identity must not do.
    static func hue(for seed: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Double(hash % 3600) / 3600
    }
}

#Preview {
    LazyVGrid(columns: ShoutKitLayout.artworkColumns, spacing: ShoutKitSpacing.medium) {
        ForEach(["KEXP 90.3 FM", "RTL", "102.7 KIIS FM", "WALM Radio", "BBC Radio 6 Music"], id: \.self) { name in
            ArtworkPlaceholder(seed: name)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: ShoutKitRadius.card, style: .continuous))
        }
    }
    .padding()
}

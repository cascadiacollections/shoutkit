import SwiftUI

public enum ShoutKitSpacing {
    public static let extraSmall: CGFloat = 6
    public static let small: CGFloat = 10
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let extraLarge: CGFloat = 34
}

public enum ShoutKitRadius {
    public static let small: CGFloat = 10
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let card: CGFloat = 20
}

public enum ShoutKitLayout {
    /// Adaptive columns for station-row collections: one column at iPhone
    /// widths, two or more as the window widens (iPad, Split View, Stage
    /// Manager). The minimum is the narrowest supported pane — a 320 pt
    /// Split View / Slide Over window minus the screens' 16 pt horizontal
    /// padding — because an adaptive grid honors its minimum even when the
    /// container is narrower, overflowing instead of shrinking. The maximum
    /// keeps a row from stretching across a full iPad screen, which pushes
    /// the play affordance arm's-length from the label.
    public static let stationColumns = [
        GridItem(
            .adaptive(minimum: 288, maximum: 640),
            spacing: ShoutKitSpacing.small,
            alignment: .top
        )
    ]

    /// Adaptive columns for poster tiles — square artwork with a name and one
    /// line of metadata under it.
    ///
    /// The minimum is what makes this a *grid* rather than a list: two columns
    /// on every supported iPhone width, three or more as the window widens. It
    /// is deliberately below the smallest iPhone half-width (a 320 pt Split View
    /// pane less 32 pt of padding leaves 144 per column at two columns), because
    /// an adaptive grid honors its minimum even when the container is narrower
    /// and would otherwise overflow. The maximum stops a tile from ballooning
    /// into a poster on iPad, where the answer to more width is more stations
    /// on screen, not larger ones.
    public static let artworkColumns = [
        GridItem(
            .adaptive(minimum: 140, maximum: 220),
            spacing: ShoutKitSpacing.medium,
            alignment: .top
        )
    ]
}

public extension Color {
    /// Brand accent — used for tint, active playback, and prominent controls.
    ///
    /// Two appearances rather than one fixed value. The light-mode blue is dark
    /// enough to read as text on white, which makes it *too* dark to read as
    /// tinted text or a glyph on a near-black background — the same ink can't
    /// serve both, so dark mode gets a lifted variant at comparable contrast.
    static let shoutKitAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.69, blue: 0.98, alpha: 1)
            : UIColor(red: 0.04, green: 0.44, blue: 0.72, alpha: 1)
    })

    /// A warmer secondary accent, used for the favorited heart. Lifted in dark
    /// appearance for the same reason as the accent above.
    static let shoutKitHighlight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.48, blue: 0.49, alpha: 1)
            : UIColor(red: 0.85, green: 0.24, blue: 0.25, alpha: 1)
    })

    /// The canvas discovery surfaces sit on.
    ///
    /// The system grouped background, not a hand-mixed near-white/near-black:
    /// it's the appearance `shoutKitCardBackground`, `List`'s inset-grouped
    /// style, and Liquid Glass are all tuned against, and it tracks the
    /// contexts a fixed color can't — sheets, popovers, and elevated
    /// presentations shift it, and Increase Contrast deepens it.
    static let shoutKitBackground = Color(.systemGroupedBackground)

    /// Fill for content cards sitting on ``shoutKitBackground``. Paired with it
    /// by the system, so the two keep a legible step apart in every appearance
    /// instead of collapsing to white-on-white or black-on-black.
    static let shoutKitCardBackground = Color(.secondarySystemGroupedBackground)
}

public extension LinearGradient {
    /// A soft brand gradient for spotlight/hero surfaces. Explicitly isolated:
    /// a static's default value evaluates in a nonisolated context even under
    /// default MainActor isolation, and it reads the isolated Color tokens.
    @MainActor
    static let shoutKitSpotlight = LinearGradient(
        colors: [Color.shoutKitAccent, Color.shoutKitAccent.opacity(0.65), Color.shoutKitHighlight.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public extension Font {
    static let shoutKitSectionTitle = Font.title2.weight(.bold)
    static let shoutKitCardTitle = Font.headline
}

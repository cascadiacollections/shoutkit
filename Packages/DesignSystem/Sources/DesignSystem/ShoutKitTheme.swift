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

public extension Color {
    /// Brand accent — used for tint, active playback, and prominent controls.
    static let shoutKitAccent = Color(red: 0.04, green: 0.44, blue: 0.72)

    /// A warmer secondary accent for editorial spotlights.
    static let shoutKitHighlight = Color(red: 0.94, green: 0.35, blue: 0.36)

    /// Primary background that adapts to light and dark appearance so Liquid Glass
    /// surfaces layer correctly in both.
    static let shoutKitBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
            : UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
    })

    static let shoutKitInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.97, alpha: 1)
            : UIColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)
    })
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

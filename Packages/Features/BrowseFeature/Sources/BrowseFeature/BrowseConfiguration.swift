/// Compile-time switches for the browse surfaces.
enum BrowseConfiguration {
    /// The featured-station spotlight banner on Listen Now and Browse.
    /// Configured off for beta 1 — it's a static pick (first directory result),
    /// not editorial content, so it wasn't earning its hero placement. The card
    /// and its wiring are kept; flip this to bring it back.
    static let showsFeaturedSpotlight = false
}

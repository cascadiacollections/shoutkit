import Foundation

/// Cleans up station names as ingested from directory sources (Radio-Browser,
/// SHOUTcast) before they're stored on ``Station``. Community-maintained
/// directories are inconsistent about formatting — names arrive with
/// underscores standing in for spaces and bracketed/parenthesized tags
/// (`[HD]`, `(128k)`) that describe the feed rather than the station.
public enum StationNameFormatter {
    /// Matches a bracketed or parenthesized clutter tag, e.g. `[HD]` or `(128k)`.
    private static let clutterTagPattern = #"\[[^\]]{0,24}\]|\([^\)]{0,24}\)"#

    public static func normalize(_ rawName: String) -> String {
        let name = rawName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: clutterTagPattern, with: "", options: .regularExpression)
        return name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}

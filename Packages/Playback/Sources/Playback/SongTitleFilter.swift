import Foundation

/// A conservative gate for whether parsed ICY track info looks like an actual
/// song, applied before it reaches the now-playing surface or listening
/// history. Broadcasters' real song titles are far too varied to enumerate, so
/// this defaults to keeping everything and rejects only on a positive signal
/// of junk: a bare URL, the station's own name, promotional copy, or a single
/// unadorned ID token.
public enum SongTitleFilter {
    /// Substrings seen in broadcaster promo copy that leaks into `StreamTitle`
    /// between songs. Lowercased, checked as substring containment.
    private static let promoPhrases: Set<String> = [
        "now playing", "listen live", "on air", "follow us", "like us",
        "text the word", "text to win", "call now", "visit us", "check us out",
        "download our app", "commercial break", "stay tuned", "coming up next",
        "back after this", "brought to you by",
    ]

    /// Bare single-word placeholders broadcasters send when no track is
    /// actually known, distinct from a legitimately one-word song title.
    private static let junkSingleWords: Set<String> = [
        "unknown", "stream", "live", "offline", "test", "advertisement",
    ]

    public static func isLikelySongTitle(_ info: AudioTrackInfo, stationName: String) -> Bool {
        guard let title = info.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.isEmpty == false else {
            return false
        }

        let candidates = [title, info.artist].compactMap { $0 }
        if candidates.contains(where: looksLikeURL) { return false }
        if candidates.contains(where: { matchesStationName($0, stationName: stationName) }) { return false }
        if candidates.contains(where: containsPromoPhrasing) { return false }
        if info.artist == nil, isBareSingleWordID(title) { return false }
        return true
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.contains("http://") || lowercased.contains("https://") || lowercased.contains("www.") {
            return true
        }

        // A bare domain, e.g. "kexp.org", with no other words around it.
        guard text.contains(where: \.isWhitespace) == false else { return false }
        let knownTLDs = [".com", ".org", ".net", ".fm", ".io", ".co"]
        return knownTLDs.contains { lowercased.hasSuffix($0) || lowercased.contains("\($0)/") }
    }

    private static func matchesStationName(_ text: String, stationName: String) -> Bool {
        let normalizedStation = normalizeForComparison(stationName)
        guard normalizedStation.isEmpty == false else { return false }
        return normalizeForComparison(text) == normalizedStation
    }

    /// Strips everything but letters/digits so punctuation and spacing
    /// differences between a `StreamTitle` station plug and the canonical
    /// station name (e.g. "KEXP 90.3 FM" vs. "KEXP903FM") don't defeat the match.
    private static func normalizeForComparison(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init)
            .reduce(into: "") { $0.append($1) }
    }

    private static func containsPromoPhrasing(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return promoPhrases.contains { lowercased.contains($0) }
    }

    /// A single token with no artist is either a real one-word song title or a
    /// placeholder ID — only the latter carries a digit or is a known filler.
    private static func isBareSingleWordID(_ title: String) -> Bool {
        guard title.contains(where: \.isWhitespace) == false else { return false }
        if junkSingleWords.contains(title.lowercased()) { return true }
        return title.contains(where: \.isNumber)
    }
}

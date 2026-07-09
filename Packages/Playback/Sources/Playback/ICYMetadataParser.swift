import Foundation

/// Parses ICY (SHOUTcast/Icecast) and broadcaster-HLS stream metadata into
/// structured track info. Pure string logic, deliberately independent of any
/// player type so it compiles and tests on every platform.
///
/// There is no single spec broadcasters agree on. In the wild we've seen:
/// - Classic ICY: a semicolon-terminated `key='value';` sequence, canonically
///   `StreamTitle='Artist - Song';StreamUrl='…';`, where the artist/title live
///   together in one field.
/// - Comma-separated, double-quoted broadcaster HLS metadata (Z100/
///   iHeartRadio-style): `title="Boom Boom Pow",artist=Black Eyed Peas`, with
///   title/artist already split into separate fields.
/// - Triton Digital-style HLS cue metadata: comma- *or* space-separated
///   `key="value"` pairs, e.g. `TrackId=…,length=…,text=…` or
///   `text="…" amgTrackId="…" length="…"`, where `text` bundles
///   "Artist - Title" like classic `StreamTitle` (or, between songs, an ad-
///   break marker like `"Spot Block End"` with no song info at all).
/// - **Nested** dialects: iHeart wraps a whole cue block *inside* the classic
///   ICY field, with a leading empty-artist separator to boot. Captured live
///   from Z100 (WHTZ): `StreamTitle=' - text="Spot Block End"
///   amgTrackId="9876543" length="00:00:00"';` — so every extraction step
///   must re-check its result for another layer of wire format.
///
/// Rather than whitelisting every dialect's exact key set, ``fields(from:)``
/// detects wire format *structurally* — any string that fully tokenizes into
/// two or more `key=value` pairs — so an unfamiliar broadcaster's field names
/// (`TrackId`, `length`, …) don't leak onto screen as raw text even before we
/// know what they mean. Only recognized title-bearing keys are ever surfaced;
/// everything else is silently dropped. As a last resort, anything that still
/// looks like `key="value"` soup after unwrapping is suppressed, never shown.
public enum ICYMetadataParser {
    /// Keys recognized on their own even as the *only* field in a block (a
    /// lone `StreamTitle='…';` is common; a lone `TrackId=123` is not
    /// something we'd want to guess about, so it isn't here).
    private static let recognizedSingleFieldKeys: Set<String> = [
        "streamtitle", "streamurl", "title", "artist", "album", "text",
    ]

    /// Keys whose value bundles "Artist - Title" together, checked in
    /// priority order.
    private static let combinedTitleKeys = ["streamtitle", "text"]

    /// Triton Digital ad-break cue markers delivered in the `text` field.
    /// These describe the break, not what's playing — showing them as a song
    /// title reads as a glitch, so they're suppressed (the UI falls back to
    /// the station name).
    private static let adCueMarkers: Set<String> = ["spot block start", "spot block end"]
    private static let advertisementCuePhrases: Set<String> = [
        "spot block",
        "commercial break",
        "ad break"
    ]

    /// Dialects nest at most one level in observed streams; the guard is just
    /// a backstop against a pathological self-referencing block.
    private static let maxNestingDepth = 4

    public static func parseTrack(from rawMetadata: String) -> AudioTrackInfo {
        parse(rawMetadata, depth: 0)
    }

    private static func parse(_ rawMetadata: String, depth: Int) -> AudioTrackInfo {
        let suppressed = AudioTrackInfo(title: nil, artist: nil)
        let suppressedAdBreak = AudioTrackInfo(title: nil, artist: nil, isAdvertisement: true)
        guard depth < maxNestingDepth else { return suppressed }

        if let fields = fields(from: rawMetadata) {
            // A combined field's value may itself be another wire-format
            // layer (iHeart nests cue blocks inside StreamTitle) — recurse.
            for key in combinedTitleKeys {
                if let combined = fields[key] {
                    return parse(combined, depth: depth + 1)
                }
            }

            if fields["title"] != nil || fields["artist"] != nil {
                let title = fields["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = fields["artist"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let title, artist == nil, isAdvertisementMarker(title) {
                    return suppressedAdBreak
                }
                return AudioTrackInfo(
                    title: title?.isEmpty == false ? title : nil,
                    artist: artist?.isEmpty == false ? artist : nil
                )
            }

            // Recognized wire format (e.g. cue metadata with only
            // TrackId/length), but no title-bearing key — suppress rather
            // than display an unrecognized key dump.
            return suppressed
        }

        let info = splitArtistTitle(rawMetadata)
        guard let title = info.title else { return info }

        // A leading " - " can hide a nested block from the tokenizer
        // (captured live: StreamTitle=' - text="Spot Block End" …'); the
        // split strips it, so re-check the title half for wire format.
        if fields(from: title) != nil {
            return parse(title, depth: depth + 1)
        }

        if info.artist == nil, isAdvertisementMarker(title) {
            return suppressedAdBreak
        }

        // Last-resort guard for dialects the tokenizer can't decompose (bad
        // key characters, mismatched quotes): key="value" soup must never be
        // displayed as a track title.
        if title.contains("=\"") || title.contains("='") {
            return suppressed
        }

        return info
    }

    /// Tokenizes a wire-format metadata block into lowercased-key fields, e.g.
    /// `["streamtitle": "Artist - Song", "streamurl": "https://…"]` or
    /// `["trackid": "123", "text": "Artist - Song"]`. Returns nil when the
    /// string doesn't fully decompose into `key=value` pairs, or decomposes
    /// into just one pair whose key isn't independently recognizable — so
    /// callers can treat it as an already-extracted plain title instead (this
    /// keeps a legitimate title like `E=MC² - Song` out of the tokenizer).
    ///
    /// No dialect defines escaping, so a quoted value ends at the first
    /// occurrence of its quote character that is itself followed by another
    /// field boundary (a `key=` start, a separator, or end of string) — see
    /// ``closingQuote(in:quote:)``. This tolerates apostrophes inside titles
    /// like `StreamTitle='Don't Stop';` and `'Rock 'n' Roll'` without being
    /// fooled by them. Unquoted values end at the next pair separator.
    public static func fields(from rawMetadata: String) -> [String: String]? {
        var fields: [String: String] = [:]
        var rest = Substring(rawMetadata)
        while true {
            rest = rest.drop { $0 == ";" || $0 == "," || $0.isWhitespace }
            if rest.isEmpty { break }
            guard let equals = rest.firstIndex(of: "=") else { return nil }
            let key = rest[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, key.allSatisfy(isKeyCharacter) else { return nil }
            rest = rest[rest.index(after: equals)...]

            let value: String
            if let quote = rest.first, quote == "'" || quote == "\"" {
                rest = rest.dropFirst()
                if let close = closingQuote(in: rest, quote: quote) {
                    value = String(rest[..<close.lowerBound])
                    rest = rest[close.upperBound...]
                } else {
                    value = String(rest)
                    rest = rest[rest.endIndex...]
                }
            } else if let separator = rest.firstIndex(where: { $0 == ";" || $0 == "," }) {
                value = String(rest[..<separator])
                rest = rest[separator...]
            } else {
                value = String(rest)
                rest = rest[rest.endIndex...]
            }
            fields[key] = value
        }

        guard fields.count >= 2 || fields.keys.contains(where: recognizedSingleFieldKeys.contains) else {
            return nil
        }
        return fields
    }

    /// Finds the quote character that actually closes a value: the earliest
    /// occurrence of `quote` after which the remainder looks like a genuine
    /// field boundary (see ``looksLikeFieldBoundary(after:in:)``), skipping
    /// any occurrence that's just part of the value itself (an apostrophe in
    /// a title, say).
    private static func closingQuote(in text: Substring, quote: Character) -> Range<Substring.Index>? {
        var searchFrom = text.startIndex
        while let quoteIndex = text[searchFrom...].firstIndex(of: quote) {
            let afterQuote = text.index(after: quoteIndex)
            if looksLikeFieldBoundary(after: afterQuote, in: text) {
                return quoteIndex..<afterQuote
            }
            searchFrom = afterQuote
        }
        return nil
    }

    /// True when `index` is the end of the string, or is followed — after
    /// skipping any separator/whitespace characters — by what looks like the
    /// start of the next `key=` pair. Separators vary by dialect (`;`, `,`,
    /// or a bare space in Triton Digital's `key="value" key="value"` cue
    /// metadata), so this checks structurally rather than for one fixed
    /// character.
    private static func looksLikeFieldBoundary(after index: Substring.Index, in text: Substring) -> Bool {
        var cursor = index
        while cursor != text.endIndex, text[cursor] == ";" || text[cursor] == "," || text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        if cursor == text.endIndex { return true }

        var keyEnd = cursor
        while keyEnd != text.endIndex, isKeyCharacter(text[keyEnd]) {
            keyEnd = text.index(after: keyEnd)
        }
        return keyEnd != cursor && keyEnd != text.endIndex && text[keyEnd] == "="
    }

    private static func isKeyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func isAdvertisementMarker(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if adCueMarkers.contains(normalized) {
            return true
        }
        return advertisementCuePhrases.contains(normalized)
    }

    /// The separator is searched in the raw string: trimming first would destroy
    /// a leading separator in empty-artist titles like `" - Orphan Title"`.
    private static func splitArtistTitle(_ streamTitle: String) -> AudioTrackInfo {
        guard let separator = streamTitle.range(of: " - ") else {
            let trimmed = streamTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return AudioTrackInfo(title: trimmed.isEmpty ? nil : trimmed, artist: nil)
        }

        let artist = String(streamTitle[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(streamTitle[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return AudioTrackInfo(title: title.isEmpty ? nil : title, artist: artist.isEmpty ? nil : artist)
    }
}

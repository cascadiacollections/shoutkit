@testable import Playback
import Testing

/// Wire-format coverage for the ICY `key='value';` metadata block. The plain
/// artist/title split cases live in `PlaybackControllerTests`.
struct ICYMetadataParserTests {
    // MARK: - Full wire-format blocks

    @Test func `wire format block extracts stream title`() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle='Radiohead - Weird Fishes';StreamUrl='https://kexp.org';",
        )
        #expect(info.artist == "Radiohead")
        #expect(info.title == "Weird Fishes")
    }

    @Test func `wire format block with empty stream title yields no track`() {
        let info = ICYMetadataParser.parseTrack(from: "StreamTitle='';StreamUrl='';")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func `wire format block without stream title never shows raw block`() {
        let info = ICYMetadataParser.parseTrack(from: "StreamUrl='https://example.com';")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func `apostrophe inside quoted value is preserved`() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle='Journey - Don't Stop Believin';StreamUrl='';",
        )
        #expect(info.artist == "Journey")
        #expect(info.title == "Don't Stop Believin")
    }

    @Test func `keys are case insensitive`() {
        let info = ICYMetadataParser.parseTrack(from: "streamtitle='Solo Jingle';")
        #expect(info.artist == nil)
        #expect(info.title == "Solo Jingle")
    }

    @Test func `missing trailing semicolon still parses`() {
        let info = ICYMetadataParser.parseTrack(from: "StreamTitle='Artist - Song'")
        #expect(info.artist == "Artist")
        #expect(info.title == "Song")
    }

    @Test func `unquoted value from noncompliant server parses`() {
        let info = ICYMetadataParser.parseTrack(from: "StreamTitle=Artist - Song;")
        #expect(info.artist == "Artist")
        #expect(info.title == "Song")
    }

    /// An unquoted value containing a comma must not end at it: cutting there
    /// leaves a remainder that can't tokenize, which used to fail the whole
    /// block and leak the raw wire text ("StreamTitle=Earth, Wind & Fire" as
    /// the artist) to the display and listening history.
    @Test func `unquoted value containing comma parses whole`() {
        let info = ICYMetadataParser.parseTrack(from: "StreamTitle=Earth, Wind & Fire - September;")
        #expect(info.artist == "Earth, Wind & Fire")
        #expect(info.title == "September")
    }

    @Test func `unquoted artist value containing comma parses whole`() {
        let info = ICYMetadataParser.parseTrack(from: "title=Boom,artist=Tyler, The Creator")
        #expect(info.title == "Boom")
        #expect(info.artist == "Tyler, The Creator")
    }

    @Test func `unquoted value still ends at separator before next pair`() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle=Artist - Song;StreamUrl=https://example.com/a,b",
        )
        #expect(info.artist == "Artist")
        #expect(info.title == "Song")
    }

    // MARK: - Broadcaster HLS dialect (comma-separated, double-quoted; e.g. Z100/iHeartRadio)

    @Test func `hls dialect extracts title and empty artist`() {
        let info = ICYMetadataParser.parseTrack(from: "title=\"Boom Boom Pow\",artist=")
        #expect(info.title == "Boom Boom Pow")
        #expect(info.artist == nil)
    }

    @Test func `hls dialect extracts title and artist separately`() {
        let info = ICYMetadataParser.parseTrack(from: "title=\"Boom Boom Pow\",artist=\"Black Eyed Peas\"")
        #expect(info.title == "Boom Boom Pow")
        #expect(info.artist == "Black Eyed Peas")
    }

    @Test func `hls dialect with no title or artist yields no track`() {
        let info = ICYMetadataParser.parseTrack(from: "title=,artist=")
        #expect(info.title == nil)
        #expect(info.artist == nil)
    }

    @Test func `hls dialect leading with artist key still detected`() {
        let info = ICYMetadataParser.parseTrack(from: "artist=\"Black Eyed Peas\",title=\"Boom Boom Pow\"")
        #expect(info.title == "Boom Boom Pow")
        #expect(info.artist == "Black Eyed Peas")
    }

    // MARK: - Triton-style HLS cue metadata (TrackId=…,length=…,text=…)

    @Test func `cue metadata extracts text as combined artist title`() {
        let info = ICYMetadataParser.parseTrack(
            from: "TrackId=8462532111,length=180,text=Journey - Don't Stop Believin",
        )
        #expect(info.artist == "Journey")
        #expect(info.title == "Don't Stop Believin")
    }

    @Test func `cue metadata without text suppresses rather than showing raw keys`() {
        let info = ICYMetadataParser.parseTrack(from: "TrackId=8462532111,length=")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func `cue metadata with empty text suppresses`() {
        let info = ICYMetadataParser.parseTrack(from: "TrackId=8462532111,length=,text=")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    // Space, not comma, separated — seen on Z100's ad-break cue: an actual
    // captured raw string was `text="Spot Block End" amgTrackId="9876543"
    // length="00:00:00"`. The marker describes the ad break, not a song, so
    // it's suppressed entirely rather than shown as a title.
    @Test func `space separated ad cue marker is suppressed`() {
        let info = ICYMetadataParser.parseTrack(
            from: "text=\"Spot Block End\" amgTrackId=\"9876543\" length=\"00:00:00\"",
        )
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func `ad cue start marker is suppressed case insensitively`() {
        let info = ICYMetadataParser.parseTrack(from: "text=\"SPOT BLOCK START\" adContext=\"12345\"")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func `space separated cue metadata splits artist title in text field`() {
        let info = ICYMetadataParser.parseTrack(
            from: "text=\"Journey - Don't Stop Believin\" amgTrackId=\"123\" length=\"00:00:00\"",
        )
        #expect(info.artist == "Journey")
        #expect(info.title == "Don't Stop Believin")
    }

    @Test func `space separated cue metadata ignores unrecognized trailing key`() {
        let info = ICYMetadataParser.parseTrack(from: "text=\"Boom Boom Pow\" adContext=\"12345\"")
        #expect(info.artist == nil)
        #expect(info.title == "Boom Boom Pow")
    }

    @Test func `embedded apostrophes surrounding A word do not confuse the closer`() {
        let info = ICYMetadataParser.parseTrack(from: "StreamTitle='Artist - Rock 'n' Roll';StreamUrl='';")
        #expect(info.artist == "Artist")
        #expect(info.title == "Rock 'n' Roll")
    }

    // MARK: - Nested dialects (iHeart wraps cue blocks inside StreamTitle)

    /// Captured live from Z100 (WHTZ) via an ICY probe of
    /// https://stream.revma.ihrhls.com/zc1469 — note the leading " - " inside
    /// the StreamTitle value, which hides the nested block from a naive split.
    @Test func `nested cue block inside stream title is suppressed`() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle=' - text=\"Spot Block End\" amgTrackId=\"9876543\" length=\"00:00:00\"';",
        )
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func `nested song block inside stream title extracts title and artist`() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle=' - title=\"Boom Boom Pow\",artist=\"Black Eyed Peas\","
                + "song_spot=\"M\" MediaBaseId=\"1187579\" itunesTrackId=\"0\" amgTrackId=\"-1\"';StreamUrl='';",
        )
        #expect(info.artist == "Black Eyed Peas")
        #expect(info.title == "Boom Boom Pow")
    }

    @Test func `nested combined title inside cue text still splits`() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle=' - text=\"Journey - Don't Stop Believin\" amgTrackId=\"123\"';",
        )
        #expect(info.artist == "Journey")
        #expect(info.title == "Don't Stop Believin")
    }

    // MARK: - Last-resort soup guard

    @Test func `untokenizable key value soup is suppressed not displayed`() {
        // "x-key" fails key validation (dash), so the tokenizer rejects the
        // block — the fallback guard must still keep it off screen.
        let info = ICYMetadataParser.parseTrack(from: "x-key=\"value\" other=\"thing\"")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    // MARK: - Fields tokenizer

    @Test func `fields tokenizes all pairs`() throws {
        let fields = try #require(ICYMetadataParser.fields(
            from: "StreamTitle='A - B';StreamUrl='https://example.com/art.jpg';",
        ))
        #expect(fields["streamtitle"] == "A - B")
        #expect(fields["streamurl"] == "https://example.com/art.jpg")
    }

    @Test func `fields returns nil for plain titles`() {
        #expect(ICYMetadataParser.fields(from: "Radiohead - Weird Fishes") == nil)
        #expect(ICYMetadataParser.fields(from: "Station Jingle") == nil)
    }

    // MARK: - Plain titles must never be mistaken for wire format

    @Test func `title containing equals is not tokenized`() {
        let info = ICYMetadataParser.parseTrack(from: "E=MC² - Song 2")
        #expect(info.artist == "E=MC²")
        #expect(info.title == "Song 2")
    }

    @Test func `plain titles still pass through unchanged`() {
        let info = ICYMetadataParser.parseTrack(from: " - Orphan Title")
        #expect(info.artist == nil)
        #expect(info.title == "Orphan Title")
    }
}

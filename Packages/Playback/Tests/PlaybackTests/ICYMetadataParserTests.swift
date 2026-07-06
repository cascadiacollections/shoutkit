import Testing

@testable import Playback

/// Wire-format coverage for the ICY `key='value';` metadata block. The plain
/// artist/title split cases live in `PlaybackControllerTests`.
struct ICYMetadataParserTests {
    // MARK: - Full wire-format blocks

    @Test func wireFormatBlockExtractsStreamTitle() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle='Radiohead - Weird Fishes';StreamUrl='https://kexp.org';"
        )
        #expect(info.artist == "Radiohead")
        #expect(info.title == "Weird Fishes")
    }

    @Test func wireFormatBlockWithEmptyStreamTitleYieldsNoTrack() {
        let info = ICYMetadataParser.parseTrack(from: "StreamTitle='';StreamUrl='';")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func wireFormatBlockWithoutStreamTitleNeverShowsRawBlock() {
        let info = ICYMetadataParser.parseTrack(from: "StreamUrl='https://example.com';")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func apostropheInsideQuotedValueIsPreserved() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle='Journey - Don't Stop Believin';StreamUrl='';"
        )
        #expect(info.artist == "Journey")
        #expect(info.title == "Don't Stop Believin")
    }

    @Test func keysAreCaseInsensitive() {
        let info = ICYMetadataParser.parseTrack(from: "streamtitle='Solo Jingle';")
        #expect(info.artist == nil)
        #expect(info.title == "Solo Jingle")
    }

    @Test func missingTrailingSemicolonStillParses() {
        let info = ICYMetadataParser.parseTrack(from: "StreamTitle='Artist - Song'")
        #expect(info.artist == "Artist")
        #expect(info.title == "Song")
    }

    @Test func unquotedValueFromNoncompliantServerParses() {
        let info = ICYMetadataParser.parseTrack(from: "StreamTitle=Artist - Song;")
        #expect(info.artist == "Artist")
        #expect(info.title == "Song")
    }

    // MARK: - Broadcaster HLS dialect (comma-separated, double-quoted; e.g. Z100/iHeartRadio)

    @Test func hlsDialectExtractsTitleAndEmptyArtist() {
        let info = ICYMetadataParser.parseTrack(from: "title=\"Boom Boom Pow\",artist=")
        #expect(info.title == "Boom Boom Pow")
        #expect(info.artist == nil)
    }

    @Test func hlsDialectExtractsTitleAndArtistSeparately() {
        let info = ICYMetadataParser.parseTrack(from: "title=\"Boom Boom Pow\",artist=\"Black Eyed Peas\"")
        #expect(info.title == "Boom Boom Pow")
        #expect(info.artist == "Black Eyed Peas")
    }

    @Test func hlsDialectWithNoTitleOrArtistYieldsNoTrack() {
        let info = ICYMetadataParser.parseTrack(from: "title=,artist=")
        #expect(info.title == nil)
        #expect(info.artist == nil)
    }

    @Test func hlsDialectLeadingWithArtistKeyStillDetected() {
        let info = ICYMetadataParser.parseTrack(from: "artist=\"Black Eyed Peas\",title=\"Boom Boom Pow\"")
        #expect(info.title == "Boom Boom Pow")
        #expect(info.artist == "Black Eyed Peas")
    }

    // MARK: - Triton-style HLS cue metadata (TrackId=…,length=…,text=…)

    @Test func cueMetadataExtractsTextAsCombinedArtistTitle() {
        let info = ICYMetadataParser.parseTrack(from: "TrackId=8462532111,length=180,text=Journey - Don't Stop Believin")
        #expect(info.artist == "Journey")
        #expect(info.title == "Don't Stop Believin")
    }

    @Test func cueMetadataWithoutTextSuppressesRatherThanShowingRawKeys() {
        let info = ICYMetadataParser.parseTrack(from: "TrackId=8462532111,length=")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func cueMetadataWithEmptyTextSuppresses() {
        let info = ICYMetadataParser.parseTrack(from: "TrackId=8462532111,length=,text=")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    // Space, not comma, separated — seen on Z100's ad-break cue: an actual
    // captured raw string was `text="Spot Block End" amgTrackId="9876543"
    // length="00:00:00"`. The marker describes the ad break, not a song, so
    // it's suppressed entirely rather than shown as a title.
    @Test func spaceSeparatedAdCueMarkerIsSuppressed() {
        let info = ICYMetadataParser.parseTrack(
            from: "text=\"Spot Block End\" amgTrackId=\"9876543\" length=\"00:00:00\""
        )
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func adCueStartMarkerIsSuppressedCaseInsensitively() {
        let info = ICYMetadataParser.parseTrack(from: "text=\"SPOT BLOCK START\" adContext=\"12345\"")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func spaceSeparatedCueMetadataSplitsArtistTitleInTextField() {
        let info = ICYMetadataParser.parseTrack(
            from: "text=\"Journey - Don't Stop Believin\" amgTrackId=\"123\" length=\"00:00:00\""
        )
        #expect(info.artist == "Journey")
        #expect(info.title == "Don't Stop Believin")
    }

    @Test func spaceSeparatedCueMetadataIgnoresUnrecognizedTrailingKey() {
        let info = ICYMetadataParser.parseTrack(from: "text=\"Boom Boom Pow\" adContext=\"12345\"")
        #expect(info.artist == nil)
        #expect(info.title == "Boom Boom Pow")
    }

    @Test func embeddedApostrophesSurroundingAWordDoNotConfuseTheCloser() {
        let info = ICYMetadataParser.parseTrack(from: "StreamTitle='Artist - Rock 'n' Roll';StreamUrl='';")
        #expect(info.artist == "Artist")
        #expect(info.title == "Rock 'n' Roll")
    }

    // MARK: - Nested dialects (iHeart wraps cue blocks inside StreamTitle)

    // Captured live from Z100 (WHTZ) via an ICY probe of
    // https://stream.revma.ihrhls.com/zc1469 — note the leading " - " inside
    // the StreamTitle value, which hides the nested block from a naive split.
    @Test func nestedCueBlockInsideStreamTitleIsSuppressed() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle=' - text=\"Spot Block End\" amgTrackId=\"9876543\" length=\"00:00:00\"';"
        )
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    @Test func nestedSongBlockInsideStreamTitleExtractsTitleAndArtist() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle=' - title=\"Boom Boom Pow\",artist=\"Black Eyed Peas\",song_spot=\"M\" MediaBaseId=\"1187579\" itunesTrackId=\"0\" amgTrackId=\"-1\"';StreamUrl='';"
        )
        #expect(info.artist == "Black Eyed Peas")
        #expect(info.title == "Boom Boom Pow")
    }

    @Test func nestedCombinedTitleInsideCueTextStillSplits() {
        let info = ICYMetadataParser.parseTrack(
            from: "StreamTitle=' - text=\"Journey - Don't Stop Believin\" amgTrackId=\"123\"';"
        )
        #expect(info.artist == "Journey")
        #expect(info.title == "Don't Stop Believin")
    }

    // MARK: - Last-resort soup guard

    @Test func untokenizableKeyValueSoupIsSuppressedNotDisplayed() {
        // "x-key" fails key validation (dash), so the tokenizer rejects the
        // block — the fallback guard must still keep it off screen.
        let info = ICYMetadataParser.parseTrack(from: "x-key=\"value\" other=\"thing\"")
        #expect(info.artist == nil)
        #expect(info.title == nil)
    }

    // MARK: - Fields tokenizer

    @Test func fieldsTokenizesAllPairs() throws {
        let fields = try #require(ICYMetadataParser.fields(
            from: "StreamTitle='A - B';StreamUrl='https://example.com/art.jpg';"
        ))
        #expect(fields["streamtitle"] == "A - B")
        #expect(fields["streamurl"] == "https://example.com/art.jpg")
    }

    @Test func fieldsReturnsNilForPlainTitles() {
        #expect(ICYMetadataParser.fields(from: "Radiohead - Weird Fishes") == nil)
        #expect(ICYMetadataParser.fields(from: "Station Jingle") == nil)
    }

    // MARK: - Plain titles must never be mistaken for wire format

    @Test func titleContainingEqualsIsNotTokenized() {
        let info = ICYMetadataParser.parseTrack(from: "E=MC² - Song 2")
        #expect(info.artist == "E=MC²")
        #expect(info.title == "Song 2")
    }

    @Test func plainTitlesStillPassThroughUnchanged() {
        let info = ICYMetadataParser.parseTrack(from: " - Orphan Title")
        #expect(info.artist == nil)
        #expect(info.title == "Orphan Title")
    }
}

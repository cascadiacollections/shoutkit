import Testing

@testable import Playback

struct SongTitleFilterTests {
    @Test func realSongPasses() {
        let info = AudioTrackInfo(title: "Weird Fishes", artist: "Radiohead")
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == true)
    }

    @Test func oneWordSongWithArtistPasses() {
        let info = AudioTrackInfo(title: "Halo", artist: "Beyoncé")
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == true)
    }

    @Test func noTitlePasses() {
        let info = AudioTrackInfo(title: nil, artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func urlIsRejected() {
        let info = AudioTrackInfo(title: "https://kexp.org", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func bareDomainIsRejected() {
        let info = AudioTrackInfo(title: "kexp.org", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func stationsOwnNameIsRejected() {
        let info = AudioTrackInfo(title: "KEXP 90.3 FM", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP 90.3 FM") == false)
    }

    @Test func promoPhrasingIsRejected() {
        let info = AudioTrackInfo(title: "Listen Live on the KEXP app", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func bareSingleWordIDIsRejected() {
        let info = AudioTrackInfo(title: "Stream1", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func realOneWordTitleWithNoArtistPasses() {
        let info = AudioTrackInfo(title: "Thriller", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == true)
    }
}

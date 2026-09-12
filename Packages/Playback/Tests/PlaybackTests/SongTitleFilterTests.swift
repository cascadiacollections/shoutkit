@testable import Playback
import Testing

struct SongTitleFilterTests {
    @Test func `real song passes`() {
        let info = AudioTrackInfo(title: "Weird Fishes", artist: "Radiohead")
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == true)
    }

    @Test func `one word song with artist passes`() {
        let info = AudioTrackInfo(title: "Halo", artist: "Beyoncé")
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == true)
    }

    @Test func `no title passes`() {
        let info = AudioTrackInfo(title: nil, artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func `url is rejected`() {
        let info = AudioTrackInfo(title: "https://kexp.org", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func `bare domain is rejected`() {
        let info = AudioTrackInfo(title: "kexp.org", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func `stations own name is rejected`() {
        let info = AudioTrackInfo(title: "KEXP 90.3 FM", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP 90.3 FM") == false)
    }

    @Test func `promo phrasing is rejected`() {
        let info = AudioTrackInfo(title: "Listen Live on the KEXP app", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func `bare single word ID is rejected`() {
        let info = AudioTrackInfo(title: "Stream1", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == false)
    }

    @Test func `real one word title with no artist passes`() {
        let info = AudioTrackInfo(title: "Thriller", artist: nil)
        #expect(SongTitleFilter.isLikelySongTitle(info, stationName: "KEXP") == true)
    }
}

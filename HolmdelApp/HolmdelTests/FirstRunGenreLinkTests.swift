import Foundation
@testable import Holmdel
import Testing

@MainActor
struct FirstRunGenreLinkTests {
    @Test(arguments: FirstRunGenre.allCases)
    func `an allow-listed genre is saved and case is ignored`(_ genre: FirstRunGenre) throws {
        let defaults = try makeDefaults()
        let mixedCase = genre.rawValue.uppercased()
        let url = try url("holmdel://welcome?genre=\(mixedCase)")

        #expect(FirstRunGenre.capture(from: url, defaults: defaults))
        #expect(FirstRunGenre.saved(in: defaults) == genre)
        #expect(defaults.string(forKey: FirstRunGenre.key) == genre.rawValue)
    }

    @Test func `scheme host and query name are case insensitive and whitespace is trimmed`() throws {
        let defaults = try makeDefaults()
        let url = try url("HOLMDEL://Welcome?Genre=%20Jazz%20")

        #expect(FirstRunGenre.genre(matching: url) == .jazz)
        #expect(FirstRunGenre.capture(from: url, defaults: defaults))
        #expect(FirstRunGenre.saved(in: defaults) == .jazz)
    }

    @Test(arguments: [
        "holmdel://welcome?genre=pop",
        "holmdel://welcome?genre=",
        "holmdel://welcome?genre=%20%20",
        "holmdel://welcome",
        "holmdel://welcome?genre=\(String(repeating: "x", count: 256))",
        "holmdel://station?name=KEXP&streamURL=https://example.com/live.mp3",
        "holmdel://play?id=kexp&name=KEXP",
        "https://example.com/welcome?genre=rock",
        "holmdel://settings?genre=news",
    ])
    func `unknown oversized and non-welcome links are ignored`(urlString: String) throws {
        let defaults = try makeDefaults()
        defaults.set(FirstRunGenre.talk.rawValue, forKey: FirstRunGenre.key)
        let url = try url(urlString)

        #expect(FirstRunGenre.genre(matching: url) == nil)
        #expect(FirstRunGenre.capture(from: url, defaults: defaults) == false)
        #expect(FirstRunGenre.saved(in: defaults) == .talk)
    }

    @Test func `the first genre query item wins and other items are not stored`() throws {
        let defaults = try makeDefaults()
        let url = try url("holmdel://welcome?genre=news&genre=rock&id=not-a-device")

        #expect(FirstRunGenre.capture(from: url, defaults: defaults))
        #expect(defaults.string(forKey: FirstRunGenre.key) == "news")
        #expect(defaults.object(forKey: "id") == nil)
    }

    @Test func `router keeps a valid genre pending and ignores a station link`() throws {
        let defaults = try makeDefaults()
        let router = WelcomeGenreRouter()
        let welcome = try url("holmdel://welcome?genre=country")
        let station = try url("holmdel://station?id=kexp&name=KEXP")

        #expect(router.open(url: station, defaults: defaults) == false)
        #expect(router.pending == nil)
        #expect(FirstRunGenre.saved(in: defaults) == nil)

        #expect(router.open(url: welcome, defaults: defaults))
        #expect(router.pending == .country)
        #expect(FirstRunGenre.saved(in: defaults) == .country)
        #expect(router.consumePending(.country))
        #expect(router.pending == nil)
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "FirstRunGenreLinkTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

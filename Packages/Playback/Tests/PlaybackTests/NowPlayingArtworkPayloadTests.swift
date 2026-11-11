import Foundation
@testable import Playback
import Testing

/// A 2xx artwork response that is really a web page — a broadcaster's maintenance
/// page or a parked domain answering on the old image path — must be treated as a
/// failed fetch, not handed to ImageIO on every system artwork request.
struct NowPlayingArtworkPayloadTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])

    @Test func `HTML content type is A web page`() {
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: "text/html", data: png))
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: "TEXT/HTML", data: png))
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: "application/xhtml+xml", data: png))
    }

    @Test func `HTML body is A web page whatever the content type claims`() {
        let page = Data("<!doctype html>\n<html lang=\"en\">".utf8)
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: "image/png", data: page))
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: nil, data: Data("  \n<HTML><head>".utf8)))
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: nil, data: Data([0xEF, 0xBB, 0xBF]) + page))
    }

    @Test func `image bytes under A sloppy content type are left to the decoder`() {
        // radio-browser favicons routinely arrive as octet-stream, text/plain, or
        // untyped; rejecting those would drop artwork that decodes fine.
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: "image/png", data: png) == false)
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: "application/octet-stream", data: png) == false)
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: "text/plain", data: png) == false)
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: nil, data: png) == false)
    }

    @Test func `SVG is not mistaken for HTML`() {
        let svg = Data("<?xml version=\"1.0\"?><svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: "image/svg+xml", data: svg) == false)
    }

    @Test func `empty body is not A web page`() {
        #expect(NowPlayingArtworkPayload.isWebPage(mimeType: nil, data: Data()) == false)
    }
}

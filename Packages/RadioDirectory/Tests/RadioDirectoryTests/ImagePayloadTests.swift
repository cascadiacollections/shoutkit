import Foundation
import RadioDirectory
import Testing

/// A 2xx artwork response that is really a web page — a broadcaster's maintenance
/// page or a parked domain answering on the old image path — must be treated as a
/// failed fetch, not handed to ImageIO on every system artwork request.
struct ImagePayloadTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])

    @Test func `HTML content type is A web page`() {
        #expect(ImagePayload.isWebPage(mimeType: "text/html", data: png))
        #expect(ImagePayload.isWebPage(mimeType: "TEXT/HTML", data: png))
        #expect(ImagePayload.isWebPage(mimeType: "application/xhtml+xml", data: png))
    }

    @Test func `HTML body is A web page whatever the content type claims`() {
        let page = Data("<!doctype html>\n<html lang=\"en\">".utf8)
        #expect(ImagePayload.isWebPage(mimeType: "image/png", data: page))
        #expect(ImagePayload.isWebPage(mimeType: nil, data: Data("  \n<HTML><head>".utf8)))
        #expect(ImagePayload.isWebPage(mimeType: nil, data: Data([0xEF, 0xBB, 0xBF]) + page))
    }

    @Test func `image bytes under A sloppy content type are left to the decoder`() {
        // radio-browser favicons routinely arrive as octet-stream, text/plain, or
        // untyped; rejecting those would drop artwork that decodes fine.
        #expect(ImagePayload.isWebPage(mimeType: "image/png", data: png) == false)
        #expect(ImagePayload.isWebPage(mimeType: "application/octet-stream", data: png) == false)
        #expect(ImagePayload.isWebPage(mimeType: "text/plain", data: png) == false)
        #expect(ImagePayload.isWebPage(mimeType: nil, data: png) == false)
    }

    @Test func `SVG is not mistaken for HTML`() {
        let svg = Data("<?xml version=\"1.0\"?><svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        #expect(ImagePayload.isWebPage(mimeType: "image/svg+xml", data: svg) == false)
    }

    @Test func `empty body is not A web page`() {
        #expect(ImagePayload.isWebPage(mimeType: nil, data: Data()) == false)
    }
}

/// Answers every request with one canned response.
private struct OneResponseTransport: HTTPTransporting {
    let data: Data
    let response: URLResponse

    func send(_: URLRequest) async throws -> (Data, URLResponse) {
        (data, response)
    }
}

/// `imageData(for:)` is what every artwork loader (now-playing, rows, hero)
/// fetches through, so a maintenance page fails the same way everywhere.
struct ImageDataTests {
    private let url = URL(string: "https://station.example/icon.png")

    private func fetch(status: Int, contentType: String?, body: Data) async throws -> Data {
        let url = try #require(url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: contentType.map { ["Content-Type": $0] },
        ))
        let transport = OneResponseTransport(data: body, response: response)
        return try await transport.imageData(for: URLRequest(url: url))
    }

    @Test func `a 200 maintenance page fails like A dead link`() async {
        await #expect(throws: URLError.self) {
            try await fetch(
                status: 200,
                contentType: "text/html; charset=utf-8",
                body: Data("<!doctype html><title>Listen Live</title>".utf8),
            )
        }
    }

    @Test func `an image passes through unchanged`() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(try await fetch(status: 200, contentType: "image/png", body: png) == png)
    }

    @Test func `an error status still surfaces as one`() async {
        await #expect(throws: HTTPTransportError.httpStatus(503)) {
            try await fetch(status: 503, contentType: "text/html", body: Data("<html>".utf8))
        }
    }
}

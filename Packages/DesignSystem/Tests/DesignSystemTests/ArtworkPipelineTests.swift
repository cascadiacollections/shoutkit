import Foundation
@testable import DesignSystem
import RadioDirectory
import Testing
import UIKit

@MainActor
struct ArtworkPipelineTests {
    @Test func `extension cache limits are stricter than the app`() {
        let app = ArtworkCacheLimits.application
        let widget = ArtworkCacheLimits.appExtension

        #expect(widget.memoryCostBytes < app.memoryCostBytes)
        #expect(widget.memoryCountLimit < app.memoryCountLimit)
        #expect(widget.diskByteLimit < app.diskByteLimit)
        #expect(widget.memoryCostBytes <= 4 * 1024 * 1024)
        #expect(widget.diskByteLimit <= 8 * 1024 * 1024)
    }

    @Test func `production artwork and speculative sessions share one pipeline`() {
        #expect(ArtworkTransportIdentity.identifier(of: URLSessionHTTPTransport.artwork) != nil)
        #expect(
            ArtworkTransportIdentity.identifier(of: URLSessionHTTPTransport.artwork)
                == ArtworkTransportIdentity.identifier(of: URLSessionHTTPTransport.artwork),
        )
        let store = ArtworkPipelineStore.shared
        let display = store.route(for: URLSessionHTTPTransport.artwork)
        let speculative = store.route(for: URLSessionHTTPTransport.speculative)
        #expect(display.speculative == false)
        #expect(speculative.speculative == true)
        #expect(display.pipeline === speculative.pipeline)
    }

    @Test func `a repeated load does not fetch again`() async throws {
        let transport = ScriptedImageTransport(body: png(side: 8))
        let url = try uniqueURL()

        let first = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport)
        let second = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport)

        #expect(first != nil)
        #expect(second != nil)
        #expect(await transport.sends == 1)
    }

    @Test func `two sizes of one url share the download`() async throws {
        let transport = ScriptedImageTransport(body: png(side: 64))
        let url = try uniqueURL()

        _ = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 16, transport: transport)
        _ = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport)

        #expect(await transport.sends == 1)
    }

    @Test func `concurrent loads coalesce to one fetch`() async throws {
        let transport = HoldingImageTransport(body: png(side: 8))
        let url = try uniqueURL()

        let first = Task {
            await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport)
        }
        #expect(await transport.waitUntilSending())
        let second = Task {
            await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport)
        }
        for _ in 0 ..< 40 {
            await Task.yield()
        }
        #expect(await transport.sends == 1)
        await transport.release()

        let images = await (first.value, second.value)
        #expect(images.0 != nil)
        #expect(images.1 != nil)
        #expect(await transport.sends == 1)
    }

    @Test func `a failed fetch is not cached`() async throws {
        let transport = ScriptedImageTransport(body: png(side: 8))
        await transport.setFailure(URLError(.networkConnectionLost))
        let url = try uniqueURL()

        let failed = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport)
        await transport.setFailure(nil)
        let recovered = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport)

        #expect(failed == nil)
        #expect(recovered != nil)
        #expect(await transport.sends == 2)
    }

    @Test func `an html body is a failed fetch and is not cached`() async throws {
        let html = Data("<!doctype html><html><body>down</body></html>".utf8)
        let transport = ScriptedImageTransport(body: html, mimeType: "text/html")
        let url = try uniqueURL()

        let failed = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport)
        let again = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport)

        #expect(failed == nil)
        #expect(again == nil)
        #expect(await transport.sends == 2)
    }

    @Test func `oversized artwork is downsampled to the requested pixel size`() async throws {
        let transport = ScriptedImageTransport(body: png(side: 180))
        let url = try uniqueURL()

        let image = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 40, transport: transport)
        let cgImage = try #require(image?.cgImage)

        #expect(cgImage.width <= 40)
        #expect(cgImage.height <= 40)
        #expect(cgImage.width > 0)
    }

    private func uniqueURL() throws -> URL {
        try #require(URL(string: "https://example.invalid/artwork/\(UUID().uuidString).png"))
    }

    private func png(side: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.pngData { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}

private actor ScriptedImageTransport: HTTPTransporting {
    private let body: Data
    private let mimeType: String
    private var failure: URLError?
    private(set) var sends = 0

    init(body: Data, mimeType: String = "image/png") {
        self.body = body
        self.mimeType = mimeType
    }

    func setFailure(_ failure: URLError?) {
        self.failure = failure
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        sends += 1
        if let failure {
            throw failure
        }
        let url = request.url ?? URL(fileURLWithPath: "/artwork")
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mimeType],
        ) else {
            throw URLError(.badServerResponse)
        }
        return (body, response)
    }
}

/// Blocks inside `send` so a test can observe how many fetches started before
/// letting them finish.
private actor HoldingImageTransport: HTTPTransporting {
    private let body: Data
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var sends = 0

    init(body: Data) {
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        sends += 1
        if released == false {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        let url = request.url ?? URL(fileURLWithPath: "/artwork")
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"],
        ) else {
            throw URLError(.badServerResponse)
        }
        return (body, response)
    }

    func waitUntilSending() async -> Bool {
        for _ in 0 ..< 1_000 {
            if sends > 0 { return true }
            await Task.yield()
        }
        return false
    }

    func release() {
        released = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

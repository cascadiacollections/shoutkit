@testable import DesignSystem
import Foundation
import RadioDirectory
import Testing
import UIKit

/// The unregistered path: DesignSystem's own fetch-and-downsample, which is
/// what previews, these tests, and outside adopters get. Nothing here calls
/// `ArtworkImageSource.register(_:)`.
@MainActor
struct ArtworkImageSourceTests {
    @Test func `unregistered loads downsample to the requested size`() async throws {
        let transport = HeldImageTransport(body: png(side: 180), holds: false)
        let url = try #require(URL(string: "https://example.invalid/\(UUID().uuidString).png"))

        let image = await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 40, transport: transport)
        let cgImage = try #require(image?.cgImage)

        #expect(cgImage.width <= 40)
        #expect(cgImage.height <= 40)
    }

    /// A row that scrolls away cancels its own task. The download it started
    /// keeps going so it can land in the cache for the next appearance.
    @Test func `cancelling the caller does not cancel the download`() async throws {
        let transport = HeldImageTransport(body: png(side: 8), holds: true)
        let url = try #require(URL(string: "https://example.invalid/\(UUID().uuidString).png"))

        let row = Task { await ArtworkThumbnailLoader.thumbnail(for: url, maxPixelSize: 32, transport: transport) }
        #expect(await transport.waitUntilSending())
        row.cancel()
        await transport.release()
        _ = await row.value

        #expect(await transport.waitUntilFinished())
        #expect(await transport.sawCancellation == false)
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

/// Optionally blocks inside `send` until released, and records whether the
/// task running it was cancelled by the time it resumed.
private actor HeldImageTransport: HTTPTransporting {
    private let body: Data
    private var holds: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var sends = 0
    private(set) var finished = 0
    private(set) var sawCancellation = false

    init(body: Data, holds: Bool) {
        self.body = body
        self.holds = holds
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        sends += 1
        if holds {
            await withCheckedContinuation { continuations.append($0) }
        }
        sawCancellation = sawCancellation || Task.isCancelled
        finished += 1
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
        await poll { sends > 0 }
    }

    func waitUntilFinished() async -> Bool {
        await poll { finished > 0 }
    }

    func release() {
        holds = false
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }

    private func poll(_ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 200 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

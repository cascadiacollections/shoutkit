@testable import ArtworkPipelineNuke
import CoreGraphics
import Foundation
import Nuke
import RadioDirectory
import Testing

/// Drives the production pipeline's shape — lane routing, disk cache,
/// `.storeOriginalData` — with fake transports in place of the two
/// production sessions, and a disk cache in a scratch directory.
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
        let store = ArtworkPipelineStore(
            visible: URLSessionHTTPTransport.artwork,
            speculative: URLSessionHTTPTransport.speculative,
            limits: .application,
            dataCache: nil,
        )
        #expect(ArtworkTransportIdentity.identifier(of: URLSessionHTTPTransport.artwork) != nil)
        let display = store.route(for: URLSessionHTTPTransport.artwork)
        let speculative = store.route(for: URLSessionHTTPTransport.speculative)
        #expect(display.lane == .visible)
        #expect(speculative.lane == .speculative)
        #expect(display.pipeline === speculative.pipeline)
    }

    @Test func `a repeated load does not fetch again`() async throws {
        let transport = ScriptedImageTransport(body: png(side: 8))
        let fixture = try Fixture(visible: transport)
        defer { fixture.tearDown() }
        let url = try uniqueURL()

        let first = await fixture.load(url, maxPixelSize: 32, over: transport)
        let second = await fixture.load(url, maxPixelSize: 32, over: transport)

        #expect(first != nil)
        #expect(second != nil)
        #expect(await transport.sends == 1)
    }

    @Test func `two sizes of one url share the download`() async throws {
        let transport = ScriptedImageTransport(body: png(side: 64))
        let fixture = try Fixture(visible: transport)
        defer { fixture.tearDown() }
        let url = try uniqueURL()

        _ = await fixture.load(url, maxPixelSize: 16, over: transport)
        _ = await fixture.load(url, maxPixelSize: 32, over: transport)

        #expect(await transport.sends == 1)
    }

    @Test func `concurrent loads coalesce to one fetch`() async throws {
        let transport = HoldingImageTransport(body: png(side: 8))
        let fixture = try Fixture(visible: transport)
        defer { fixture.tearDown() }
        let url = try uniqueURL()

        let first = Task { await fixture.load(url, maxPixelSize: 32, over: transport) }
        #expect(await eventually { await transport.sends > 0 })
        let second = Task { await fixture.load(url, maxPixelSize: 32, over: transport) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.sends == 1)
        await transport.release()

        let images = await (first.value, second.value)
        #expect(images.0 != nil)
        #expect(images.1 != nil)
        #expect(await transport.sends == 1)
    }

    /// A visible request must never join a speculative download: the
    /// speculative session refuses on cellular and in Low Data Mode, and a
    /// visible row that inherited that refusal would keep its placeholder.
    @Test func `a visible load does not wait on a pending speculative one`() async throws {
        let speculative = HoldingImageTransport(body: png(side: 8), failAfterRelease: true)
        let visible = ScriptedImageTransport(body: png(side: 8))
        let fixture = try Fixture(visible: visible, speculative: speculative)
        defer { fixture.tearDown() }
        let url = try uniqueURL()

        let prefetch = Task { await fixture.load(url, maxPixelSize: 32, isPrefetch: true, over: speculative) }
        #expect(await eventually { await speculative.sends == 1 })

        let onScreen = Task { await fixture.load(url, maxPixelSize: 32, over: visible) }
        let reachedVisibleSession = await eventually { await visible.sends == 1 }
        // Released either way so a regression fails here instead of hanging.
        await speculative.release()

        #expect(reachedVisibleSession)
        #expect(await onScreen.value != nil)
        #expect(await prefetch.value == nil)
    }

    @Test func `a failed fetch is not cached`() async throws {
        let transport = ScriptedImageTransport(body: png(side: 8))
        await transport.setFailure(URLError(.networkConnectionLost))
        let fixture = try Fixture(visible: transport)
        defer { fixture.tearDown() }
        let url = try uniqueURL()

        let failed = await fixture.load(url, maxPixelSize: 32, over: transport)
        await transport.setFailure(nil)
        let recovered = await fixture.load(url, maxPixelSize: 32, over: transport)

        #expect(failed == nil)
        #expect(recovered != nil)
        #expect(await transport.sends == 2)
    }

    @Test func `an html body is a failed fetch and is not cached`() async throws {
        let html = Data("<!doctype html><html><body>down</body></html>".utf8)
        let transport = ScriptedImageTransport(body: html, mimeType: "text/html")
        let fixture = try Fixture(visible: transport)
        defer { fixture.tearDown() }
        let url = try uniqueURL()

        let failed = await fixture.load(url, maxPixelSize: 32, over: transport)
        let again = await fixture.load(url, maxPixelSize: 32, over: transport)

        #expect(failed == nil)
        #expect(again == nil)
        #expect(await transport.sends == 2)
    }

    /// Nuke stores the original bytes before decoding them. Nuke 13.2.3 does
    /// fall back to the network when a disk copy fails to decode, so this is
    /// not a stuck placeholder — but bytes that are not an image should not
    /// take disk space or cost a failed decode on every later request.
    @Test func `an undecodable body is not stored on disk`() async throws {
        let garbage = Data(repeating: 0x5A, count: 256)
        let transport = ScriptedImageTransport(body: garbage, mimeType: "image/png")
        let fixture = try Fixture(visible: transport)
        defer { fixture.tearDown() }
        let url = try uniqueURL()

        let failed = await fixture.load(url, maxPixelSize: 32, over: transport)
        #expect(failed == nil)
        #expect(fixture.dataCache.cachedData(for: url.absoluteString) == nil)

        await transport.setBody(png(side: 8))
        #expect(await fixture.load(url, maxPixelSize: 32, over: transport) != nil)
        #expect(fixture.dataCache.cachedData(for: url.absoluteString) != nil)
    }

    @Test func `oversized artwork is downsampled to the requested pixel size`() async throws {
        let transport = ScriptedImageTransport(body: png(side: 180))
        let fixture = try Fixture(visible: transport)
        defer { fixture.tearDown() }
        let url = try uniqueURL()

        let image = try #require(await fixture.load(url, maxPixelSize: 40, over: transport))

        #expect(image.width <= 40)
        #expect(image.height <= 40)
        #expect(image.width > 0)
    }

    /// `value as AnyObject` boxes a struct, so a struct transport must not be
    /// keyed on that box: two of them would land on whichever pipeline the
    /// reused box address last named.
    @Test func `two struct transports never share a pipeline`() async throws {
        let store = ArtworkPipelineStore(
            visible: URLSessionHTTPTransport.artwork,
            speculative: URLSessionHTTPTransport.speculative,
            limits: .application,
            dataCache: nil,
        )
        let url = try uniqueURL()
        let working = ValueTransport(body: png(side: 8))
        let broken = ValueTransport(body: nil)

        #expect(ArtworkTransportIdentity.object(of: working) == nil)
        let first = await store.image(for: url, maxPixelSize: 32, isPrefetch: false, transport: working)
        let second = await store.image(for: url, maxPixelSize: 32, isPrefetch: false, transport: broken)

        #expect(first != nil)
        #expect(second == nil)
        #expect(working.counter.value == 1)
        #expect(broken.counter.value == 1)
        #expect(store.customPipelineCount == 0)
    }

    /// A non-production pipeline has no disk cache and lives only as long as
    /// its transport.
    @Test func `a custom transport's pipeline is memory only and released with it`() async throws {
        let store = ArtworkPipelineStore(
            visible: URLSessionHTTPTransport.artwork,
            speculative: URLSessionHTTPTransport.speculative,
            limits: .application,
            dataCache: nil,
        )
        let url = try uniqueURL()
        let released = WeakReference()
        do {
            let transport = ScriptedImageTransport(body: png(side: 8))
            released.object = transport
            #expect(store.route(for: transport).pipeline.configuration.dataCache == nil)
            #expect(await store.image(for: url, maxPixelSize: 32, isPrefetch: false, transport: transport) != nil)
            #expect(store.customPipelineCount == 1)
        }
        #expect(await eventually { released.object == nil })
        #expect(store.customPipelineCount == 0)
    }

    private func uniqueURL() throws -> URL {
        try #require(URL(string: "https://example.invalid/artwork/\(UUID().uuidString).png"))
    }
}

// MARK: - Fixture

private struct Fixture {
    let store: ArtworkPipelineStore
    let dataCache: DataCache
    let directory: URL

    init(visible: any HTTPTransporting, speculative: any HTTPTransporting = UnusedTransport()) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "ArtworkPipelineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        dataCache = try DataCache(path: directory)
        store = ArtworkPipelineStore(
            visible: visible,
            speculative: speculative,
            limits: .application,
            dataCache: dataCache,
        )
    }

    func load(
        _ url: URL,
        maxPixelSize: CGFloat,
        isPrefetch: Bool = false,
        over transport: any HTTPTransporting,
    ) async -> CGImage? {
        await store.image(for: url, maxPixelSize: maxPixelSize, isPrefetch: isPrefetch, transport: transport)
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }
}

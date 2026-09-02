import Foundation
import Testing
@testable import RadioDirectory

private actor SequenceTransport: HTTPTransporting {
    private var results: [Result<(Data, URLResponse), Error>]

    init(_ results: [Result<(Data, URLResponse), Error>]) {
        self.results = results
    }

    func send(_: URLRequest) async throws -> (Data, URLResponse) {
        guard results.isEmpty == false else {
            throw HTTPTransportError.transport("No queued response")
        }
        return try results.removeFirst().get()
    }
}

struct HTTPTransportTests {
    @Test
    func retriesThroughTransientFailures() async throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = SequenceTransport([
            .failure(HTTPTransportError.transport("offline")),
            .success((Data("ok".utf8), response))
        ])

        let data = try await transport.retryingData(
            retryPolicy: RetryPolicy(maximumRetries: 1, timeout: 1, baseDelay: 0),
            totalAttempts: 2,
            shouldRetry: { error in
                (error as? HTTPTransportError) == .transport("offline")
            },
            request: { _ in URLRequest(url: URL(string: "https://example.com")!) }
        )

        #expect(String(bytes: data, encoding: .utf8) == "ok")
    }

    @Test
    func validatesHTTPStatusCodes() async throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 503,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = SequenceTransport([
            .success((Data(), response))
        ])

        await #expect(throws: HTTPTransportError.httpStatus(503)) {
            try await transport.data(for: URLRequest(url: URL(string: "https://example.com")!))
        }
    }

    @Test
    func artworkConfigurationYieldsPriorityWithoutRefusingConstrainedNetworks() throws {
        let configuration = URLSessionHTTPTransport.artworkConfiguration()

        // `.background` so artwork doesn't contend with the audio stream for
        // scheduling priority on a weak connection.
        #expect(configuration.networkServiceType == .background)
        // But still permitted on cellular/Low Data Mode: a listener actively
        // playing a station still expects to see its art, unlike the
        // look-ahead prefetch `speculativeConfiguration()` suppresses.
        #expect(configuration.allowsConstrainedNetworkAccess)
        #expect(configuration.allowsExpensiveNetworkAccess)
        #expect(configuration.waitsForConnectivity == false)
    }

    @Test
    func nowPlayingArtworkConfigurationStaysOutOfTheDeferrableTier() {
        let configuration = URLSessionHTTPTransport.nowPlayingArtworkConfiguration()

        // NOT `.background`: a lock screen, Live Activity, or Bluetooth head unit
        // is blocked on this image, and `MediaSessionNowPlayingCenter` will not
        // advertise artwork whose bytes it doesn't hold — so a deferred fetch is
        // no artwork for the whole track, not merely a late one. NOT
        // `.responsiveData` either; one image per track doesn't need to contend
        // with the audio stream for front-of-queue.
        #expect(configuration.networkServiceType == .default)
        #expect(configuration.allowsConstrainedNetworkAccess)
        #expect(configuration.allowsExpensiveNetworkAccess)
        #expect(configuration.waitsForConnectivity == false)
    }

    @Test
    func escapesPlusInQueryValues() throws {
        var components = try #require(URLComponents(string: "https://example.com/search"))
        components.queryItems = [URLQueryItem(name: "q", value: "C+C Music Factory")]
        components.escapePlusInQueryValues()

        #expect(components.percentEncodedQuery == "q=C%2BC%20Music%20Factory")
    }
}

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
            attempts: 2,
            shouldRetry: { error in
                (error as? HTTPTransportError) == .transport("offline")
            },
            request: { _ in URLRequest(url: URL(string: "https://example.com")!) }
        )

        #expect(String(decoding: data, as: UTF8.self) == "ok")
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
    func escapesPlusInQueryValues() throws {
        var components = try #require(URLComponents(string: "https://example.com/search"))
        components.queryItems = [URLQueryItem(name: "q", value: "C+C Music Factory")]
        components.escapePlusInQueryValues()

        #expect(components.percentEncodedQuery == "q=C%2BC%20Music%20Factory")
    }
}

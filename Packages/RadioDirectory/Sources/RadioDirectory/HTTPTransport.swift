import Foundation

public enum HTTPTransportError: Error, Equatable, Sendable {
    case transport(String?)
    case invalidResponse
    case httpStatus(Int)
}

public protocol HTTPTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

public actor URLSessionHTTPTransport: HTTPTransporting {
    public static let shared = URLSessionHTTPTransport()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw HTTPTransportError.transport(error.localizedDescription)
        }
    }
}

public extension HTTPTransporting {
    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPTransportError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw HTTPTransportError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    func retryingData(
        retryPolicy: RetryPolicy,
        attempts: Int,
        shouldRetry: @Sendable (Error) -> Bool = { _ in true },
        onRetry: @Sendable (_ attempt: Int, _ delay: TimeInterval) -> Void = { _, _ in },
        request: @Sendable (_ attempt: Int) throws -> URLRequest
    ) async throws -> Data {
        let totalAttempts = max(attempts, 1)
        var lastError: Error?

        for attempt in 0 ..< totalAttempts {
            do {
                let nextRequest = try request(attempt)
                return try await data(for: nextRequest)
            } catch {
                lastError = error
                guard shouldRetry(error), attempt < totalAttempts - 1 else {
                    break
                }

                let delay = retryPolicy.delay(forAttempt: attempt)
                onRetry(attempt, delay)
                // A cancelled sleep just skips the backoff; the next attempt's
                // network call fails fast on cancellation anyway.
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? HTTPTransportError.transport(nil)
    }
}

public extension URLComponents {
    /// `URLComponents` leaves `+` unescaped in query values, but web servers
    /// conventionally form-decode it as a space. Escape it explicitly.
    mutating func escapePlusInQueryValues() {
        if let escapedQuery = percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") {
            percentEncodedQuery = escapedQuery
        }
    }
}

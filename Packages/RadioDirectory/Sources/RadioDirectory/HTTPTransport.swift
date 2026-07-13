import Foundation
import os

public enum HTTPTransportError: Error, Equatable, Sendable {
    case transport(String)
    case invalidResponse
    case httpStatus(Int)
}

public protocol HTTPTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

public actor URLSessionHTTPTransport: HTTPTransporting {
    /// The session `shared` is built with on first access, defaulting to
    /// `URLSession.shared`. The app installs its Debug-only Pulse logging proxy
    /// here (see the app-side DebugSupport package) so this package never
    /// depends on inspection tooling.
    private static let sharedSessionOverride = OSAllocatedUnfairLock<URLSession?>(initialState: nil)

    /// Installs the session that backs `shared`. Only the first install wins,
    /// and it must happen before the first network call touches `shared` —
    /// call it at the top of the app's bootstrap, nowhere else.
    public static func installSharedSession(_ session: URLSession) {
        sharedSessionOverride.withLock { $0 = $0 ?? session }
    }

    public static let shared = URLSessionHTTPTransport(
        session: sharedSessionOverride.withLock { $0 } ?? .shared
    )

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

        guard 200..<300 ~= httpResponse.statusCode else {
            throw HTTPTransportError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    /// Runs the request builder up to `totalAttempts` times with exponential
    /// backoff delays from `retryPolicy`. `attempt` in callbacks is 0-indexed.
    /// `totalAttempts` is the full budget (initial try + retries), independent
    /// from `RetryPolicy.maximumRetries`, so callers can model custom loops
    /// (like mirror lists) while still sharing one retry implementation.
    func retryingData(
        retryPolicy: RetryPolicy,
        totalAttempts: Int,
        shouldRetry: @Sendable (Error) -> Bool = { _ in true },
        onRetry: @Sendable (_ attempt: Int, _ delay: TimeInterval) -> Void = { _, _ in },
        request: @Sendable (_ attempt: Int) throws -> URLRequest
    ) async throws -> Data {
        let maximumAttempts = max(totalAttempts, 1)
        var lastError: Error?

        for attempt in 0 ..< maximumAttempts {
            do {
                let nextRequest = try request(attempt)
                return try await data(for: nextRequest)
            } catch {
                lastError = error
                guard shouldRetry(error), attempt < maximumAttempts - 1 else {
                    break
                }

                let delay = retryPolicy.delay(forAttempt: attempt)
                onRetry(attempt, delay)
                // A cancelled sleep just skips the backoff; the next attempt's
                // network call fails fast on cancellation anyway.
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? HTTPTransportError.transport("Unknown transport error")
    }
}

public extension URLComponents {
    /// `URLComponents` leaves `+` unescaped in query values, but web servers
    /// conventionally form-decode it as a space, so "C+C" arrives as "C C".
    /// Call this after assigning `queryItems` when `+` must round-trip.
    mutating func escapePlusInQueryValues() {
        if let escapedQuery = percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") {
            percentEncodedQuery = escapedQuery
        }
    }
}

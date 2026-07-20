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
    private static let logger = Logger(
        subsystem: "ShoutKit.RadioDirectory",
        category: "URLSessionHTTPTransport"
    )
    private static let signposter = OSSignposter(
        subsystem: "ShoutKit.RadioDirectory",
        category: "URLSessionHTTPTransport"
    )

    /// The session `shared` is built with on first access, defaulting to
    /// `URLSession.shared`. The app installs its Debug-only Pulse logging proxy
    /// here (see the app-side DebugSupport package) so this package never
    /// depends on inspection tooling.
    private static let sharedSessionOverride = OSAllocatedUnfairLock<URLSession?>(initialState: nil)
    private static let sharedSessionResolved = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// Installs the session that backs `shared`. Only the first install wins,
    /// and it must happen before the first network call touches `shared` —
    /// call it at the top of the app's bootstrap, nowhere else.
    public static func installSharedSession(_ session: URLSession) {
        if sharedSessionResolved.withLock({ $0 }) {
            logger.error(
                "installSharedSession ignored because URLSessionHTTPTransport.shared was already resolved"
            )
            assertionFailure(
                "URLSessionHTTPTransport.installSharedSession must run before first access of .shared."
            )
            return
        }

        let installed = sharedSessionOverride.withLock { current -> Bool in
            guard current == nil else { return false }
            current = session
            return true
        }
        if !installed {
            logger.error("installSharedSession ignored because a shared session is already installed")
            assertionFailure(
                "URLSessionHTTPTransport.installSharedSession called more than once; first install wins."
            )
        }
    }

    public static let shared: URLSessionHTTPTransport = {
        sharedSessionResolved.withLock { $0 = true }
        return URLSessionHTTPTransport(
            session: sharedSessionOverride.withLock { $0 } ?? .shared
        )
    }()

    /// A configuration tuned for the app's interactive HTTP traffic (directory
    /// JSON and artwork): `waitsForConnectivity = false` so an offline device
    /// fails fast into the app's own retry/mirror logic instead of URLSession
    /// silently parking the request, and `.responsiveData` to hint the system
    /// scheduler that these are latency-sensitive foreground fetches. Callers
    /// still set per-request timeouts (see `RetryPolicy`). The app installs a
    /// session built from this as `shared` at bootstrap.
    public static func interactiveConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.networkServiceType = .responsiveData
        return configuration
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let signpostID = Self.signposter.makeSignpostID()
        let interval = Self.signposter.beginInterval("HTTP request", id: signpostID)
        let metricsObserver = session.delegate == nil ? TaskMetricsObserver() : nil
        do {
            let response = try await session.data(for: request, delegate: metricsObserver)
            Self.logTaskMetrics(
                metricsObserver?.metrics,
                request: request,
                response: response.1
            )
            Self.signposter.endInterval("HTTP request", interval)
            return response
        } catch {
            Self.signposter.endInterval("HTTP request", interval)
            throw HTTPTransportError.transport(error.localizedDescription)
        }
    }
}

private extension URLSessionHTTPTransport {
    static func logTaskMetrics(
        _ metrics: URLSessionTaskMetrics?,
        request: URLRequest,
        response: URLResponse
    ) {
        guard let metrics else { return }

        let transaction = metrics.transactionMetrics.last
        let host = request.url?.host ?? response.url?.host ?? "unknown"
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let summary = NetworkTimingSummary(transaction: transaction, taskInterval: metrics.taskInterval)

        logger.notice(
            """
            URLSessionTaskMetrics host=\(host, privacy: .public) \
            method=\(request.httpMethod ?? "GET", privacy: .public) \
            status=\(statusCode) dnsMs=\(summary.describe(summary.dnsMilliseconds), privacy: .public) \
            connectMs=\(summary.describe(summary.connectMilliseconds), privacy: .public) \
            tlsMs=\(summary.describe(summary.tlsMilliseconds), privacy: .public) \
            requestMs=\(summary.describe(summary.requestMilliseconds), privacy: .public) \
            responseMs=\(summary.describe(summary.responseMilliseconds), privacy: .public) \
            totalMs=\(summary.describe(summary.totalMilliseconds), privacy: .public) \
            reusedConnection=\(transaction?.isReusedConnection ?? false)
            """
        )
    }

    final class TaskMetricsObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock<URLSessionTaskMetrics?>(initialState: nil)

        var metrics: URLSessionTaskMetrics? {
            lock.withLock { $0 }
        }

        func urlSession(
            _: URLSession,
            task _: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            lock.withLock { $0 = metrics }
        }
    }

    struct NetworkTimingSummary {
        let dnsMilliseconds: Double?
        let connectMilliseconds: Double?
        let tlsMilliseconds: Double?
        let requestMilliseconds: Double?
        let responseMilliseconds: Double?
        let totalMilliseconds: Double?

        init(transaction: URLSessionTaskTransactionMetrics?, taskInterval: DateInterval) {
            dnsMilliseconds = Self.milliseconds(
                from: transaction?.domainLookupStartDate,
                to: transaction?.domainLookupEndDate
            )
            connectMilliseconds = Self.milliseconds(
                from: transaction?.connectStartDate,
                to: transaction?.connectEndDate
            )
            tlsMilliseconds = Self.milliseconds(
                from: transaction?.secureConnectionStartDate,
                to: transaction?.secureConnectionEndDate
            )
            requestMilliseconds = Self.milliseconds(
                from: transaction?.requestStartDate,
                to: transaction?.requestEndDate
            )
            responseMilliseconds = Self.milliseconds(
                from: transaction?.responseStartDate,
                to: transaction?.responseEndDate
            )
            totalMilliseconds = taskInterval.duration * 1_000
        }

        func describe(_ value: Double?) -> String {
            guard let value else { return "n/a" }
            return String(format: "%.2f", value)
        }

        private static func milliseconds(from start: Date?, to end: Date?) -> Double? {
            guard let start, let end else { return nil }
            return end.timeIntervalSince(start) * 1_000
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

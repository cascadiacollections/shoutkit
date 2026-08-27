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
        let sharedAlreadyResolved = sharedSessionResolved.withLock { resolved in resolved }
        if sharedAlreadyResolved {
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

    /// A configuration for *speculative* traffic — artwork for rows that haven't
    /// scrolled into view yet — as opposed to anything a listener is waiting on.
    ///
    /// The distinction matters because the two deserve opposite treatment under
    /// pressure. `allowsConstrainedNetworkAccess = false` means Low Data Mode
    /// suppresses this traffic outright: the user has told the system not to
    /// spend their allowance on work they didn't ask for, and a look-ahead fetch
    /// is exactly that. `allowsExpensiveNetworkAccess = false` extends the same
    /// courtesy to cellular and Personal Hotspot. `.background` (rather than
    /// `.responsiveData`) tells the scheduler nobody is blocked on these, so they
    /// yield to the directory and to artwork a visible row actually needs.
    ///
    /// A request refused by these limits fails at the URLSession layer without
    /// producing an HTTP response at all, so it leaves nothing behind: not in
    /// `URLCache`, not in the decoded-thumbnail cache (which only stores
    /// successes), and not in the in-flight table (which clears on completion).
    /// A refusal therefore can't suppress that artwork later — when the row
    /// scrolls into view, its own load is issued fresh on the interactive
    /// session. Whether *that* request succeeds is an ordinary network question,
    /// no different from any other fetch.
    public static func speculativeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.allowsExpensiveNetworkAccess = false
        configuration.networkServiceType = .background
        return configuration
    }

    /// Shared transport for speculative work. Deliberately plain rather than
    /// mirroring `shared`'s install hook: this carries no user-visible traffic,
    /// so it isn't worth routing through the Debug inspection proxy.
    public static let speculative = URLSessionHTTPTransport(
        session: URLSession(configuration: URLSessionHTTPTransport.speculativeConfiguration())
    )

    /// A configuration for artwork a listener can see *right now* — a visible
    /// row, the Now Playing hero, lock-screen and Live Activity art — as
    /// distinct from the directory JSON search that shares `interactiveConfiguration()`.
    /// Both are real, unprefetched fetches, so `allowsConstrainedNetworkAccess`
    /// and `allowsExpensiveNetworkAccess` stay at their permissive defaults: a
    /// listener actively playing a station over cellular still expects to see
    /// its art, unlike the look-ahead prefetch `speculativeConfiguration()`
    /// exists to suppress.
    ///
    /// What changes is `networkServiceType`: `.background` instead of
    /// `.responsiveData`. The audio stream itself runs through AudioStreaming's
    /// own, unconfigurable `URLSession` (see `PlaybackEngineAudioStreaming`),
    /// so this package has no way to *boost* the stream's priority — the only
    /// lever available is to stop artwork from claiming equal or better
    /// scheduling priority than it. On a weak link (LTE, 3G, a saturated
    /// Wi-Fi — the cases "5G or worse" is shorthand for), a `.responsiveData`
    /// artwork fetch and the audio stream are asking the system's cellular
    /// scheduler for the same front-of-queue treatment; `.background` yields
    /// that queue position to whatever else is moving bytes, which in this
    /// app is always the thing the listener is actually here for.
    public static func artworkConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.networkServiceType = .background
        return configuration
    }

    /// Shared transport for artwork a listener can currently see. Deliberately
    /// its own session, plain like `.speculative`'s — no Debug inspection hook
    /// yet, but unlike speculative prefetch this does carry user-visible
    /// traffic, so a future need to inspect it in Pulse is a real possibility,
    /// not a hypothetical.
    public static let artwork = URLSessionHTTPTransport(
        session: URLSession(configuration: URLSessionHTTPTransport.artworkConfiguration())
    )

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let signpostID = Self.signposter.makeSignpostID()
        let interval = Self.signposter.beginInterval("HTTP request", id: signpostID)
        // Passing a per-task delegate overrides the session delegate for that
        // callback chain. If the session has no delegate, attach a per-task
        // observer so we can log metrics. If Debug installed Pulse as the
        // session delegate, pass `nil` here so Pulse still receives metrics.
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
            // Preserve cancellation identity. Rewrapping it as a transport
            // error would make retry/mirror loops treat a deliberately
            // cancelled call (a debounced search keystroke, a torn-down view)
            // as a retryable network failure and spin through the remaining
            // attempts with doomed requests.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
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
                // Cancellation is never retryable, whatever `shouldRetry`
                // says: the caller has already abandoned the result.
                guard error is CancellationError == false,
                      shouldRetry(error), attempt < maximumAttempts - 1 else {
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

import Foundation
import Network
import os

/// Warms the network path to a set of stream hosts by opening — and immediately
/// tearing down — a transport connection to each. This primes the system's
/// (process-wide) DNS cache and TCP/TLS path state, so a later real `play()` to
/// the same host skips the cold DNS lookup and handshake.
///
/// Deliberately connection-level, not an HTTP request: it establishes the
/// transport without pulling any stream bytes, so it costs a handshake, not a
/// download. Entirely best-effort and fire-and-forget — every failure is
/// ignored, because the real play path does its own resolution and error
/// handling. The DNS/TLS warmth is shared at the OS layer, so it benefits the
/// AudioStreaming engine's own socket even though this doesn't touch it.
public actor StationConnectionPrewarmer {
    private let maxHosts: Int
    private let handshakeTimeout: TimeInterval
    private let logger = Logger(subsystem: "ShoutKit.Playback", category: "StationConnectionPrewarmer")

    /// Injected so the Low Power Mode branch is testable; production reads the
    /// live value. Sampled per call rather than captured once, because the mode
    /// flips mid-session (the system enables it at 20%, the user toggles it).
    private let isLowPowerModeEnabled: @Sendable () -> Bool

    public init(
        maxHosts: Int = 5,
        handshakeTimeout: TimeInterval = 4,
        isLowPowerModeEnabled: @escaping @Sendable () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    ) {
        self.maxHosts = maxHosts
        self.handshakeTimeout = handshakeTimeout
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    /// Warms up to `maxHosts` distinct hosts drawn from `streamURLs` (in order,
    /// so the caller's ranking — most-played/favorited first — is honored).
    ///
    /// A no-op in Low Power Mode. Prewarming spends radio time on stations the
    /// listener may never tap — up to `maxHosts` DNS lookups and TLS handshakes
    /// at launch — to save a fraction of a second on one they might. That's a
    /// good trade normally and the wrong one when the device is conserving, so
    /// the whole thing is skipped rather than trimmed. Nothing downstream cares:
    /// `play(_:)` resolves and connects on its own regardless.
    /// - Returns: how many distinct hosts were *attempted* — 0 when skipped.
    ///   Deliberately not a success count: ``warm(_:timeout:)`` treats `.ready`,
    ///   `.failed` and `.cancelled` as equally terminal and the timeout resolves
    ///   the same way, because none of them changes what the caller does next.
    ///   Callers fire and forget; the value exists so the skip is observable.
    @discardableResult
    public func prewarm(streamURLs: [URL]) async -> Int {
        guard isLowPowerModeEnabled() == false else {
            logger.debug("Skipping station prewarm: Low Power Mode is enabled")
            return 0
        }

        var seenHosts = Set<String>()
        let targets = streamURLs
            .compactMap(Target.init(url:))
            .filter { seenHosts.insert($0.dedupeKey).inserted }
            .prefix(maxHosts)

        guard targets.isEmpty == false else { return 0 }
        logger.debug("Prewarming \(targets.count, privacy: .public) station host(s)")

        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                group.addTask { [handshakeTimeout] in
                    await Self.warm(target, timeout: handshakeTimeout)
                }
            }
        }
        return targets.count
    }

    /// A resolved connection destination. Built from a stream URL, defaulting the
    /// port by scheme and deduplicating by host:port:tls so two stations on the
    /// same origin only warm it once.
    private struct Target: Sendable {
        let host: NWEndpoint.Host
        let port: NWEndpoint.Port
        let useTLS: Bool
        let dedupeKey: String

        init?(url: URL) {
            guard let host = url.host, host.isEmpty == false else { return nil }
            let useTLS = url.scheme?.lowercased() == "https"
            let resolvedPort = url.port ?? (useTLS ? 443 : 80)
            guard (1...65_535).contains(resolvedPort),
                  let port = NWEndpoint.Port(rawValue: UInt16(resolvedPort)) else { return nil }
            self.host = NWEndpoint.Host(host)
            self.port = port
            self.useTLS = useTLS
            self.dedupeKey = "\(host):\(resolvedPort):\(useTLS)"
        }
    }

    private static func warm(_ target: Target, timeout: TimeInterval) async {
        let parameters: NWParameters = target.useTLS ? .tls : .tcp
        let connection = NWConnection(host: target.host, port: target.port, using: parameters)
        let queue = DispatchQueue(label: "com.cascadiacollections.holmdel.prewarm")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // The state handler and the timeout can both fire; the lock makes
            // teardown-and-resume happen exactly once.
            let hasFinished = OSAllocatedUnfairLock(initialState: false)
            @Sendable func finish() {
                let alreadyFinished = hasFinished.withLock { finished -> Bool in
                    defer { finished = true }
                    return finished
                }
                guard alreadyFinished == false else { return }
                connection.cancel()
                continuation.resume()
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    // .ready = path fully warm (best case); .failed/.cancelled =
                    // nothing more to wait for. All three are terminal here.
                    finish()
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: finish)
            connection.start(queue: queue)
        }
    }
}

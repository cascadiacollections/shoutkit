#if DEBUG
import Foundation
import Pulse

/// Debug-only network inspection. Every Pulse reference lives in this single
/// file so the `#if DEBUG` boundary is easy to audit; nothing outside it ever
/// imports Pulse. `HTTPTransport.swift` only reaches in via ``session``, which
/// is compiled out of Release entirely.
enum PulseNetworkLogging {
    /// A `URLSession` wired with Pulse's proxy delegate. Installed as the
    /// default session behind `URLSessionHTTPTransport.shared` — the transport
    /// Radio-Browser/SHOUTcast lookups and artwork downloads use — so those
    /// requests show up in Pulse without every call site knowing about it.
    static let session = URLSession(
        configuration: .default,
        delegate: URLSessionProxyDelegate(logger: .shared),
        delegateQueue: nil
    )
}
#endif

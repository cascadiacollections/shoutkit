import Foundation
import RadioDirectory

#if DEBUG
import Pulse
#endif

/// Debug-only network inspection. Every Pulse reference in the repo lives in
/// this single app-side file so the `#if DEBUG` boundary stays easy to audit
/// and the reusable packages never declare Pulse at all; the CI `nm` check on
/// the Release binary is belt-and-suspenders on top of that.
public enum DebugNetworkInspection {
    /// Routes `URLSessionHTTPTransport.shared` — the transport Radio-Browser/
    /// SHOUTcast lookups and artwork downloads default to — through a session
    /// wired with Pulse's proxy delegate, so those requests show up in Pulse
    /// without any call site knowing about it. Must run before the first
    /// network call resolves `shared`; `AppDependencies.bootstrap()` calls it
    /// first thing. Compiles to a no-op in Release.
    public static func install() {
        #if DEBUG
        URLSessionHTTPTransport.installSharedSession(URLSession(
            configuration: .default,
            delegate: URLSessionProxyDelegate(logger: .shared),
            delegateQueue: nil
        ))
        #endif
    }
}

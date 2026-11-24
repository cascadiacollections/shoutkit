import Foundation
import Observation

/// Funnels `holmdel://welcome?genre=` links from `onOpenURL` to `RootView`.
///
/// Same shape as `StationLaunchRouter`: a link that arrives before the root
/// view exists waits in `pending`, and `RootView` drains it with
/// `.onChange(of:initial:)`. The genre is also written to UserDefaults so a
/// first launch that reads the welcome screen after this returns still sees it.
///
/// Handled before the station router. `welcome` is not a station route, and a
/// link that names a chip must not be parsed as one.
@MainActor
@Observable
final class WelcomeGenreRouter {
    private(set) var pending: FirstRunGenre?

    /// Returns false when the URL is not an allow-listed welcome genre.
    /// Nothing is stored in that case.
    @discardableResult
    func open(url: URL, defaults: UserDefaults = .standard) -> Bool {
        guard FirstRunGenre.capture(from: url, defaults: defaults),
              let genre = FirstRunGenre.saved(in: defaults)
        else {
            return false
        }
        pending = genre
        return true
    }

    /// Consumes `pending` only when it still matches `genre`, so in multi-window
    /// setups only one observer handles a given payload.
    @discardableResult
    func consumePending(_ genre: FirstRunGenre) -> Bool {
        guard pending == genre else { return false }
        pending = nil
        return true
    }
}

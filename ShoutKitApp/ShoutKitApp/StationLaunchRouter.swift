import Foundation
import Observation
import RadioDirectory

/// Funnels station deep links (`shoutkit://station?...`) from `onOpenURL` to
/// `RootView`, which owns the navigation state a launch mutates. Latest-wins:
/// a link that arrives before the root view exists waits in `pending`, and
/// `RootView` drains it with `.onChange(of:initial:)` — the `initial` pass
/// covers cold launch, so no buffering or listener handshake is needed.
///
/// Deliberately MainActor-only: `onOpenURL` delivers on the main actor and the
/// consumer is view state, so cross-actor coordination would only add
/// suspension points (and the delivery races that come with them).
@MainActor
@Observable
final class StationLaunchRouter {
    private(set) var pending: StationLink?

    func open(_ link: StationLink) {
        pending = link
    }

    /// Returns false when the URL is not a recognized station link.
    @discardableResult
    func open(url: URL) -> Bool {
        guard let link = StationLink(url: url) else {
            return false
        }

        open(link)
        return true
    }

    /// The consumer calls this after acting on `pending` so an identical link
    /// arriving later still registers as a change.
    func clearPending() {
        pending = nil
    }
}

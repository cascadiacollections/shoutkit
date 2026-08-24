import Foundation
import Observation
import RadioDirectory

/// Funnels station deep links (`holmdel://station?...`) from `onOpenURL` to
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

    /// Returns false when the activity is not a recognized station handoff payload.
    @discardableResult
    func open(userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == StationLink.handoffActivityType,
              let userInfo = userActivity.userInfo,
              let link = StationLink(handoffUserInfo: userInfo) else {
            return false
        }

        open(link)
        return true
    }

    /// Consumes `pending` only when it still matches `link`, so in multi-window
    /// setups only one observer handles a given payload.
    @discardableResult
    func consumePending(_ link: StationLink) -> Bool {
        guard pending == link else { return false }
        pending = nil
        return true
    }
}

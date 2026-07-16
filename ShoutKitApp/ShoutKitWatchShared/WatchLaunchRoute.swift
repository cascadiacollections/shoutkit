import Foundation

enum WatchLaunchRoute {
    static let playLastURL = URL(string: "shoutkit-watch://play-last")!

    static func isPlayLast(_ url: URL) -> Bool {
        url.scheme == playLastURL.scheme && url.host == playLastURL.host
    }
}

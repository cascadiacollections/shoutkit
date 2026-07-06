import Foundation

/// External destinations surfaced in Settings/About. Centralized so a repo
/// rename touches one file.
enum ProjectLinks {
    static let repository = url("https://github.com/cascadiacollections/shoutkit")
    static let issues = url("https://github.com/cascadiacollections/shoutkit/issues")
    static let sponsors = url("https://github.com/sponsors/KevinTCoughlin")
    static let radioBrowser = url("https://www.radio-browser.info")

    private static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }
}

/// App version metadata read from the main bundle.
enum AppInfo {
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

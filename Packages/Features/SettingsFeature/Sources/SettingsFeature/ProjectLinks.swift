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
    /// Short git commit the build was produced from, injected at build time via
    /// the `GIT_COMMIT_SHA` build setting (see `Config/*.xcconfig`). Nil for
    /// ad-hoc local builds that didn't pass a real value.
    static var commitSHA: String? {
        guard let raw = Bundle.main.infoDictionary?["GitCommitSHA"] as? String else { return nil }
        let sha = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sha.isEmpty, sha != "local" else { return nil }
        return sha
    }

    /// e.g. `0.2.0 (12) · a1b2c3d` — the trailing commit makes a customer
    /// screenshot map to an exact source revision for bug repro. The commit is
    /// omitted for local builds so the line stays clean during development.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        let base = "\(version) (\(build))"
        guard let commitSHA else { return base }
        return "\(base) · \(commitSHA)"
    }
}

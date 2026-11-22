import Foundation

/// Whether this build was signed, and so carries the iCloud entitlement its
/// target declares.
///
/// CloudKit does not report a missing `com.apple.developer.icloud-services`
/// entitlement as an error. It raises an exception on a queue of its own and
/// the process dies at launch, so the question has to be answered before a
/// container is opened with sync. iOS has no public way to read a process's
/// entitlements, but whether the build was signed is known when it is built:
/// each app's `Info.plist` carries `ShoutKitCodeSigningAllowed`, expanded from
/// the `CODE_SIGNING_ALLOWED` build setting. CI builds with that set to `NO`
/// (DECISIONS.md, 2026-11-22).
public enum CloudSyncEntitlement {
    /// The `Info.plist` key each app target defines as `$(CODE_SIGNING_ALLOWED)`.
    public static let infoDictionaryKey = "ShoutKitCodeSigningAllowed"

    /// `false` only when the bundle says outright that it was built unsigned.
    ///
    /// A missing or unexpanded value counts as signed. Getting that wrong
    /// crashes an unsigned build, which CI launches on every pull request;
    /// getting the opposite wrong would switch sync off in a shipped build
    /// with nothing to show for it.
    public static func isPresent(in bundle: Bundle = .main) -> Bool {
        isPresent(infoDictionaryValue: bundle.object(forInfoDictionaryKey: infoDictionaryKey))
    }

    static func isPresent(infoDictionaryValue value: Any?) -> Bool {
        guard let text = value as? String else { return true }
        return text.trimmingCharacters(in: .whitespaces).uppercased() != "NO"
    }
}

import Foundation

/// Debug-only tripwire for environment values that default to `nil` until the app
/// root injects them (`\.playbackController`, `\.libraryStore`). Feature views
/// correctly no-op when these are absent — SwiftUI previews rely on that — but a
/// production run where the root forgot to inject should fail loudly in Debug
/// rather than silently swallow every tap. No-ops entirely in Release and in
/// Xcode Previews (which legitimately never inject these).
public func assertEnvironmentInjected(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String,
    file: StaticString = #fileID,
    line: UInt = #line
) {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
    assert(condition(), message(), file: file, line: line)
    #endif
}

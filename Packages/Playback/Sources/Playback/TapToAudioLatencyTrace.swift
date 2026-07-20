import Foundation
import os

@MainActor
final class TapToAudioLatencyTrace {
    private nonisolated static let logger = Logger(subsystem: "ShoutKit.Playback", category: "TapToAudio")
    private nonisolated static let signposter = OSSignposter(subsystem: "ShoutKit.Playback", category: "TapToAudio")

    private let stationID: String
    private let prewarmEnabled: Bool
    private let startedAt = Date()
    private let signpostID: OSSignpostID
    private let interval: OSSignpostIntervalState

    private var resolvedAt: Date?
    private var outputStartedAt: Date?
    private var completed = false

    init(stationID: String, prewarmEnabled: Bool) {
        self.stationID = stationID
        self.prewarmEnabled = prewarmEnabled
        signpostID = Self.signposter.makeSignpostID()
        interval = Self.signposter.beginInterval("Tap to audio", id: signpostID)
    }

    deinit {
        guard completed == false else { return }
        completed = true
        Self.signposter.endInterval("Tap to audio", interval)
    }

    func markResolved(url: URL) {
        guard completed == false, resolvedAt == nil else { return }
        resolvedAt = Date()
        Self.signposter.emitEvent("Resolve complete", id: signpostID)
        Self.logger.notice(
            """
            TapToAudio resolved station=\(self.stationID, privacy: .public) \
            host=\(url.host ?? "unknown", privacy: .public) prewarmEnabled=\(self.prewarmEnabled)
            """
        )
    }

    func markOutputStarted() {
        guard completed == false, outputStartedAt == nil else { return }
        outputStartedAt = Date()
        Self.signposter.emitEvent("Output start", id: signpostID)
    }

    func completeIfNeeded() {
        guard completed == false else { return }
        completed = true
        Self.signposter.endInterval("Tap to audio", interval)

        let resolveMilliseconds = milliseconds(from: startedAt, to: resolvedAt)
        let outputStartMilliseconds = milliseconds(from: startedAt, to: outputStartedAt)
        let firstPlayingMilliseconds = Date().timeIntervalSince(startedAt) * 1_000

        Self.logger.notice(
            """
            TapToAudio complete station=\(self.stationID, privacy: .public) prewarmEnabled=\(self.prewarmEnabled) \
            resolveMs=\(Self.describe(resolveMilliseconds), privacy: .public) \
            outputStartMs=\(Self.describe(outputStartMilliseconds), privacy: .public) \
            firstPlayingMs=\(Self.describe(firstPlayingMilliseconds), privacy: .public)
            """
        )
    }

    func cancel() {
        guard completed == false else { return }
        completed = true
        Self.signposter.endInterval("Tap to audio", interval)
    }

    private func milliseconds(from start: Date, to end: Date?) -> Double? {
        guard let end else { return nil }
        return end.timeIntervalSince(start) * 1_000
    }

    private static func describe(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }
}

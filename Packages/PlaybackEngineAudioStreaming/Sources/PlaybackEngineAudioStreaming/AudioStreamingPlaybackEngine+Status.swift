import Foundation
import Playback

// Status attribution and duplicate suppression for the streaming adapter.
// Kept beside the delegate implementation rather than inside it so the core
// engine stays within the repository's file-length limit.
extension AudioStreamingPlaybackEngine {
    func reportFailure(_ error: PlaybackError, generation: UInt64? = nil) {
        guard hasReportedFailure == false, hasReportedEndOfStream == false else { return }
        hasReportedFailure = true
        stopClassificationTask?.cancel()
        reportStatus(.failed(error), generation: generation)
    }

    /// Claims a completed programme before the pending unexpected-stop path can
    /// report the same ending as a failure.
    func reportEndOfStream(generation: UInt64? = nil) {
        guard hasReportedEndOfStream == false, hasReportedFailure == false else { return }
        hasReportedEndOfStream = true
        stopClassificationTask?.cancel()
        reportStatus(.endOfStream, generation: generation)
    }

    /// Captures attribution before a delegate callback hops to the main actor.
    func reportStatus(_ status: AudioStatus, generation: UInt64? = nil) {
        let generation = generation ?? streamGeneration.withLock { $0 }
        onStatusChange?(AudioStatusUpdate(status, streamGeneration: generation))
    }
}

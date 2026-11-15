import AudioStreaming
import AVFoundation
import Foundation

// How a stream URL is handed to the player, split out of
// AudioStreamingPlaybackEngine.swift for the 400-line `file_length` limit.
//
// Live http(s) streams go through `SingleRequestStreamSource`, which opens one
// request instead of AudioStreaming's probe-then-reconnect: about 1.4 s off
// tap-to-audio on KEXP (DECISIONS.md, 2026-11-14). Anything else, and any
// stream the source hands back, goes through `play(url:)` as before.

extension AudioStreamingPlaybackEngine {
    /// The player's own default output format (`AudioPlayer.outputAudioFormat`,
    /// private there), which `play(source:)` needs spelled out.
    static func streamOutputFormat() -> AVAudioFormat {
        // Force-unwrap is safe: a fixed, standard PCM layout.
        // swiftlint:disable:next force_unwrapping
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: true)!
    }

    /// Starts `url` on `player`, through the single-request source when it can.
    ///
    /// Falling back re-runs the stream once through `play(url:)`, and only if it
    /// is still the stream this engine is playing: a station switch, a stop or a
    /// rejoin since then has replaced the player, changed the URL or advanced
    /// the generation, and a late fallback must not restart the old stream.
    func beginStreaming(_ url: URL, on player: AudioPlayer) {
        guard SingleRequestStreamSource.canStream(url) else {
            player.play(url: url)
            return
        }
        let generation = streamGeneration.withLock { $0 }
        // An identity, not the player: AudioPlayer isn't Sendable. A rejoin
        // replaces the player but keeps the URL and generation, so this is
        // what stops the old source's fallback restarting the rejoined stream.
        let playerID = ObjectIdentifier(player)
        let source = SingleRequestStreamSource(url: url, underlyingQueue: player.sourceQueue) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      ObjectIdentifier(self.player) == playerID,
                      self.currentURL == url,
                      self.streamGeneration.withLock({ $0 }) == generation
                else { return }
                let host = url.host ?? "?"
                Self.logger.notice("Single-request source handed back \(host, privacy: .public); using play(url:)")
                self.player.play(url: url)
            }
        }
        player.play(source: source, entryId: url.absoluteString, format: Self.streamOutputFormat())
    }
}

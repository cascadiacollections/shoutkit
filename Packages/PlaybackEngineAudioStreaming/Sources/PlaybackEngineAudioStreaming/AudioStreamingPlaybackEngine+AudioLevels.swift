import AudioLevels
import AudioStreaming
import AVFoundation
import Foundation
import Playback

/// The engine's `AudioTapPlugin` attach point: one AudioStreaming
/// `frameFiltering` entry, which taps the main mixer while it has at least one
/// entry, dispatching every rendered buffer to `audioTaps` on a non-main thread.
/// The mixer is after the equalizer and the volume ramp, so plug-ins see what
/// the listener hears, fade-in included.
///
/// Measured on macOS with KEXP: the tap delivers 4410-frame, 2-channel,
/// deinterleaved Float32 buffers at 44.1 kHz — about ten a second — even though
/// AudioStreaming requests 1024. It also works under AudioStreaming's
/// manual-rendering engine, which was not a given.
public extension AudioStreamingPlaybackEngine {
    internal nonisolated static let audioTapFilterName = "ShoutKit.AudioTaps"

    var supportsAudioTaps: Bool {
        true
    }

    func addAudioTap(_ plugin: any AudioTapPlugin) {
        let wasEmpty = audioTaps.isEmpty
        audioTaps.add(plugin)
        if wasEmpty {
            installAudioTapFilter()
        }
    }

    func removeAudioTap(_ plugin: any AudioTapPlugin) {
        audioTaps.remove(plugin)
        if audioTaps.isEmpty {
            // Removing the last entry removes the mixer tap itself.
            player.frameFiltering.remove(entry: Self.audioTapFilterName)
        }
    }

    /// Re-installs the filter on a freshly built player. Every station switch,
    /// rejoin, and media-services reset replaces `player`, and the new one's
    /// mixer has no tap.
    internal func reattachAudioTapsIfNeeded() {
        guard audioTaps.isEmpty == false else { return }
        installAudioTapFilter()
    }

    private func installAudioTapFilter() {
        player.frameFiltering.remove(entry: Self.audioTapFilterName)
        player.frameFiltering.add(entry: Self.makeAudioTapFilter(audioTaps))
    }

    /// `nonisolated` is load-bearing: the filter runs on AudioStreaming's tap
    /// thread, and a closure formed in this main-actor type would inherit
    /// main-actor isolation and trap in libdispatch's queue assertion on its
    /// first call — which a probe built the other way did.
    private nonisolated static func makeAudioTapFilter(_ taps: AudioTapPluginSet) -> FilterEntry {
        FilterEntry(name: audioTapFilterName) { buffer, time in
            taps.dispatch(buffer, at: time)
        }
    }
}

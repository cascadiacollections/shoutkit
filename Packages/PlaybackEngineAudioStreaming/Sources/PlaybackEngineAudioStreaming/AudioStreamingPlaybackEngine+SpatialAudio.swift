import AudioStreaming
import AVFoundation
import Foundation
import Playback

#if canImport(CoreMotion)
import CoreMotion
#endif

// Opt-in, headphones-only spatial audio: an `AVAudioEnvironmentNode` inserted
// at the same attach point the equalizer uses (see
// AudioStreamingPlaybackEngine+Equalizer.swift), driven by AirPods head
// tracking via `CMHeadphoneMotionManager`.
//
// This is a stereo virtualization effect — HRTF binaural rendering plus head
// tracking — not object-based spatial audio: the stream itself is plain
// stereo/mono ICY radio with no channel or object separation to spatialize.
// It's the same technique Apple applies to non-Atmos content elsewhere in the
// OS, and is presented to the user that way (see `SettingsFeature`), not as
// "real" Dolby Atmos.
//
// The whole effect is gated on `canImport(CoreMotion)`, which given this
// package's `.iOS` + `.tvOS` platform list means "not tvOS": there is no
// CoreMotion — and so no `CMHeadphoneMotionManager` — on tvOS, and head
// tracking is the point of the feature. `RadioPlaybackEngine` defaults
// `supportsSpatialAudio` to `false` and `setSpatialAudioEnabled(_:)` to a
// no-op, so leaving both out here degrades the capability rather than
// exposing a dead control (`SettingsFeature` keys its row off
// `supportsSpatialAudio`).
#if canImport(CoreMotion)
extension AudioStreamingPlaybackEngine {
    /// Fixed virtual distance (meters) placed between the listener and the
    /// stream's origin, so head rotation has a stereo image to pan around.
    /// `AVAudioEnvironmentNode.listenerPosition` and an unconfigured source's
    /// position both default to the origin, and panning is undefined at zero
    /// separation. The listener is moved back rather than the source moved
    /// forward because there's no reference to the source's own
    /// `AVAudioMixingDestination` here: `player.attach(node:)` inserts this
    /// node into AudioStreaming's internal graph without exposing the
    /// upstream node the position would normally be set on.
    private static let listenerDistance: Float = 1.0

    public var supportsSpatialAudio: Bool { true }

    public func setSpatialAudioEnabled(_ isEnabled: Bool) {
        isSpatialAudioEnabled = isEnabled
        guard isEnabled else {
            detachSpatialAudioNode()
            return
        }
        let environment = spatialAudioNode ?? attachSpatialAudioNode()
        startHeadTracking(for: environment)
    }

    /// Creates, attaches, and remembers the environment node. Called lazily
    /// from ``setSpatialAudioEnabled(_:)`` and again from
    /// `handleMediaServicesReset()` (via ``reattachSpatialAudioIfNeeded()``),
    /// since a reset tears down the whole `AVAudioEngine` this node lives in.
    @discardableResult
    func attachSpatialAudioNode() -> AVAudioEnvironmentNode {
        let environment = AVAudioEnvironmentNode()
        environment.outputType = .headphones
        environment.reverbParameters.enable = false
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: Self.listenerDistance)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        player.attach(node: environment)
        spatialAudioNode = environment
        return environment
    }

    /// Re-attaches the environment node to the rebuilt engine after a
    /// media-services reset, if spatial audio was on before the reset.
    /// Without this the effect would silently vanish on the next reset — the
    /// new `AVAudioEngine` has no memory of the old node.
    func reattachSpatialAudioIfNeeded() {
        // The reset already discarded the whole `AVAudioEngine` this node
        // lived in along with everything else, so there's nothing left to
        // detach — just forget the reference.
        spatialAudioNode = nil
        guard isSpatialAudioEnabled else { return }
        let environment = attachSpatialAudioNode()
        startHeadTracking(for: environment)
    }

    /// Stops head tracking and removes the environment node from the render
    /// chain entirely. Unlike the equalizer's "leave the node attached, apply
    /// a flat curve" approach for `.normal`, an `AVAudioEnvironmentNode`'s
    /// HRTF encoding isn't something a neutral parameter setting can make
    /// transparent — it always downmixes to a binaural signal — so turning
    /// the effect off has to mean removing the node, not just parking it.
    private func detachSpatialAudioNode() {
        headphoneMotionManager.stopDeviceMotionUpdates()
        guard let environment = spatialAudioNode else { return }
        player.detach(node: environment)
        spatialAudioNode = nil
    }

    /// Drives `environment.listenerAngularOrientation` from the connected
    /// AirPods' head tracking, so the simulated sound stage stays fixed in
    /// space as the listener turns their head. A no-op on hardware without
    /// head tracking (`isDeviceMotionAvailable == false`) or when no
    /// compatible headphones are currently connected — the HRTF rendering
    /// from ``attachSpatialAudioNode()`` still applies, just without
    /// head-tracked movement.
    private func startHeadTracking(for environment: AVAudioEnvironmentNode) {
        guard headphoneMotionManager.isDeviceMotionAvailable else { return }
        headphoneMotionManager.startDeviceMotionUpdates(to: .main) { [weak environment] motion, _ in
            // `to: .main` delivers this on the main queue already, but the
            // handler's own type carries no actor isolation the compiler can
            // see; converting to plain values here (rather than touching
            // `self`/`environment` in this closure) and hopping through a
            // `@MainActor` `Task` is what makes the capture below sound
            // rather than an unchecked escape hatch.
            guard let motion else { return }
            let attitude = motion.attitude
            let orientation = AVAudio3DAngularOrientation(
                yaw: Float(attitude.yaw * 180 / .pi),
                pitch: Float(attitude.pitch * 180 / .pi),
                roll: Float(attitude.roll * 180 / .pi)
            )
            Task { @MainActor in
                environment?.listenerAngularOrientation = orientation
            }
        }
    }
}
#else
extension AudioStreamingPlaybackEngine {
    /// Declared on every platform so `handleMediaServicesReset()` needs no
    /// `#if` of its own. There is never a spatial audio node to re-attach
    /// where CoreMotion is unavailable, because there is no way to attach one.
    func reattachSpatialAudioIfNeeded() {}
}
#endif

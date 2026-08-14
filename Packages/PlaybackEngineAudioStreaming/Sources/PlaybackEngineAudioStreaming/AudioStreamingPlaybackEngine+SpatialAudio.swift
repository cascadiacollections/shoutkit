import AudioStreaming
import AVFoundation
import CoreMotion
import Foundation
import Playback

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
            headphoneMotionManager.stopDeviceMotionUpdates()
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
        spatialAudioNode = nil
        guard isSpatialAudioEnabled else { return }
        let environment = attachSpatialAudioNode()
        startHeadTracking(for: environment)
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

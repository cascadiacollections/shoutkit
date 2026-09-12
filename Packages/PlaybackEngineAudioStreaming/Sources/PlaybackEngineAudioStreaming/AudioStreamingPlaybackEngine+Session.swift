import AudioStreaming
import AVFoundation
import Foundation
import os
import Playback

// `AudioStreamingPlaybackEngine`'s ownership of `AVAudioSession`: configuration,
// activation (and the retries an OS disruption makes necessary), teardown, and
// the notifications through which the system announces a disruption —
// interruptions, route changes, and a media-services reset. AudioStreaming
// deliberately doesn't touch the session, so all of it is ours. Split out of
// AudioStreamingPlaybackEngine.swift for the 400-line `file_length` limit CI
// enforces via `swiftlint --strict`, the same remedy as the
// `PlaybackController+Internals`/`+Recovery` splits.

extension AudioStreamingPlaybackEngine {
    private static let sessionDeactivationRetryDelay: Duration = .milliseconds(150)

    /// How long a replaced player is kept alive after `stop()`, so
    /// AudioStreaming's own asynchronous teardown can reach it. Long enough for
    /// a queue hop, short enough that the dead player's buffers aren't held for
    /// any perceptible time.
    private static let discardedPlayerTeardownGrace: Duration = .seconds(1)

    /// Backoff between reactivation attempts. `setActive(true)` legitimately fails
    /// for a moment either side of an OS disruption — the tail of a phone call,
    /// Siri still holding the session, a route still settling — and the failure
    /// used to be swallowed, so playback resumed into a session it never got and
    /// produced no audio at all. One immediate attempt plus these four retries
    /// (five in total, ~3.55 s of waiting) covers that window without spinning.
    private static let sessionActivationRetryDelays: [Duration] = [
        .milliseconds(150),
        .milliseconds(400),
        .seconds(1),
        .seconds(2),
    ]

    /// One-time session configuration, reapplied after a media-services reset
    /// (which wipes it). Category/policy are also reasserted on every activation,
    /// since that's cheap and idempotent.
    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        configureCategory(of: session)
        do {
            // Ordinary system alerts (messages, mail, most notification sounds)
            // then duck this stream instead of interrupting it. Without this a
            // single notification could pause live radio — and, if iOS omitted
            // the resume hint, leave it paused until the listener noticed.
            // Genuine interruptions (calls, alarms, Siri) still arrive normally.
            try session.setPrefersNoInterruptionsFromSystemAlerts(true)
        } catch {
            Self.logger.error(
                "Could not prefer no interruptions from system alerts: \(String(describing: error), privacy: .public)",
            )
        }
    }

    /// `.longFormAudio` is the route-sharing policy Apple specifies for music and
    /// radio: it's what makes this app the system's long-form audio app for
    /// AirPlay 2 routing and volume handling on shared routes (the watch engine
    /// already asked for it). Falling back to the default policy matters more
    /// than the policy itself — a throwing `setCategory` must not be the reason
    /// the session never activates and the stream plays silently.
    private func configureCategory(of session: AVAudioSession) {
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            Self.logger.error(
                "Long-form audio category failed, falling back: \(String(describing: error), privacy: .public)",
            )
            try? session.setCategory(.playback, mode: .default)
        }
    }

    /// Runs `body` with an active audio session, retrying activation on a short
    /// backoff when the system refuses it (see `sessionActivationRetryDelays`).
    /// If activation never succeeds the stream is *not* started: a player fed by
    /// an inactive session buffers audio nobody can hear while the app reports
    /// playing. A retryable failure is reported instead, so the controller's
    /// bounded reconnect owns the next attempt.
    func withActiveSession(_ body: @escaping @MainActor () -> Void) {
        cancelPendingSessionActivation()
        if activateSession() {
            body()
            return
        }

        sessionActivationTask = Task { @MainActor [weak self] in
            for delay in Self.sessionActivationRetryDelays {
                try? await Task.sleep(for: delay)
                guard Task.isCancelled == false, let self else { return }
                if self.activateSession() {
                    self.sessionActivationTask = nil
                    body()
                    return
                }
            }
            guard Task.isCancelled == false, let self else { return }
            self.sessionActivationTask = nil
            Self.logger.error("Audio session stayed unavailable; reporting a retryable failure")
            self.reportFailure(.streamFailed("The audio session was unavailable."))
        }
    }

    func cancelPendingSessionActivation() {
        sessionActivationTask?.cancel()
        sessionActivationTask = nil
    }

    /// - Returns: whether the session is active. The result is the point: the
    ///   `try?` this replaced hid a failed activation behind a player that then
    ///   played to nobody.
    private func activateSession() -> Bool {
        sessionDeactivationTask?.cancel()
        let session = AVAudioSession.sharedInstance()
        configureCategory(of: session)
        do {
            try session.setActive(true)
            return true
        } catch {
            Self.logger.error(
                "Audio session activation failed: \(String(describing: error), privacy: .public)",
            )
            return false
        }
    }

    func deactivateSessionAfterStop() async {
        let session = AVAudioSession.sharedInstance()

        for attempt in 0 ..< 5 {
            guard Task.isCancelled == false else { return }
            do {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
                return
            } catch {
                guard Self.shouldRetrySessionDeactivation(error), attempt < 4 else {
                    Self.logger.error(
                        "Audio session deactivation failed after stop: \(String(describing: error), privacy: .public)",
                    )
                    return
                }
                try? await Task.sleep(for: Self.sessionDeactivationRetryDelay)
            }
        }
    }

    private static func shouldRetrySessionDeactivation(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard let code = AVAudioSession.ErrorCode(rawValue: nsError.code) else {
            return false
        }
        return code == .isBusy
    }

    // MARK: - OS disruptions

    /// Observers use queue: .main throughout, so MainActor.assumeIsolated is safe
    /// inside them. One method per notification: together they overran the
    /// 50-line `function_body_length` budget, and each reads better alone anyway.
    func observeAudioSessionNotifications() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observeInterruptions(on: session, with: center)
        observeRouteChanges(on: session, with: center)
        observeMediaServicesReset(with: center)
    }

    private func observeInterruptions(on session: AVAudioSession, with center: NotificationCenter) {
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main,
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType)
            else {
                return
            }

            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)

            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .began:
                    // A pending activation retry belongs to the state before the
                    // interruption, and the session isn't ours to take during one.
                    self.cancelPendingSessionActivation()
                    self.onStatusChange?(AudioStatusUpdate(.interruptionBegan))
                case .ended:
                    // Read live rather than captured: `AVAudioSession` isn't
                    // Sendable, and this is the moment the answer matters.
                    let otherAudioIsPlaying = AVAudioSession.sharedInstance().isOtherAudioPlaying
                    Self.logger.info(
                        """
                        Interruption ended (shouldResume: \(shouldResume, privacy: .public), \
                        otherAudioIsPlaying: \(otherAudioIsPlaying, privacy: .public))
                        """,
                    )
                    self.onStatusChange?(AudioStatusUpdate(.interruptionEnded(
                        shouldResume: shouldResume,
                        otherAudioIsPlaying: otherAudioIsPlaying,
                    )))
                @unknown default:
                    break
                }
            }
        })
    }

    private func observeRouteChanges(on session: AVAudioSession, with center: NotificationCenter) {
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main,
        ) { [weak self] notification in
            guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
            else {
                return
            }

            MainActor.assumeIsolated {
                guard let self else { return }
                switch reason {
                case .oldDeviceUnavailable:
                    // Headphones unplugged: pause rather than continue on the speaker.
                    guard self.isPlayerActive else { return }
                    self.onStatusChange?(AudioStatusUpdate(.routeLost))
                case .newDeviceAvailable:
                    self.onStatusChange?(AudioStatusUpdate(.routeAvailable))
                case .unknown, .categoryChange, .override, .wakeFromSleep,
                     .noSuitableRouteForCategory, .routeConfigurationChange:
                    break
                @unknown default:
                    break
                }
            }
        })
    }

    /// `object: nil` deliberately: unlike the interruption and route-change
    /// notifications, this one is not documented as posted by the session
    /// instance, and a mismatched object filter would silently never fire — which
    /// is also why this one takes no `session` parameter.
    private func observeMediaServicesReset(with center: NotificationCenter) {
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMediaServicesReset()
            }
        })
    }

    /// Whether the player is producing — or about to produce — audio.
    private var isPlayerActive: Bool {
        player.state == .playing || player.state == .bufferring
    }

    /// The audio server crashed and restarted. Every audio object in the process
    /// is now dead — including the `AVAudioEngine` inside AudioStreaming's player
    /// — and the session's configuration went with it, so no amount of retrying
    /// the *existing* player recovers: playback stayed silent until the app was
    /// relaunched. Rebuild both, then report a retryable failure so the
    /// controller's bounded reconnect rejoins the stream from a clean player.
    private func handleMediaServicesReset() {
        Self.logger.error("Media services were reset; rebuilding the player and audio session")
        cancelPendingSessionActivation()
        sessionDeactivationTask?.cancel()
        sessionDeactivationTask = nil
        replacePlayer()
        configureSession()
        reattachEqualizerIfNeeded()
        reattachSpatialAudioIfNeeded()
        // Nothing had been selected: there is no listener-visible state to
        // update. Otherwise announce the reset without restarting playback;
        // Apple requires a new user action before media processing resumes.
        // `didRequestStop` may reflect controller-internal teardown, so listener
        // intent is decided by the controller rather than suppressed here.
        guard currentURL != nil else { return }
        onStatusChange?(AudioStatusUpdate(.mediaServicesReset))
    }

    /// Replaces the player while allowing its asynchronous teardown to finish.
    /// Callers reattach enabled effects after any required session setup.
    func replacePlayer() {
        // Late callbacks from the replaced player are ignored by the identity
        // check in the delegate methods, but it can't be dropped *silently*:
        // `AudioPlayer.deinit` closes only `audioPlayingEntry`, never
        // `audioReadingEntry`, and an abandoned reading entry takes its
        // `RemoteAudioSource` — and that source's pending retry timer — down with
        // it. AudioStreaming 1.4.4's `DispatchTimerSource.deinit` resumes the
        // timer unconditionally, which for a timer still activated by a pending
        // retry is an over-resume that aborts the process inside libdispatch. So
        // a reset arriving while a stream is mid-retry (a dead station, a
        // timeout) crashes on the way out.
        //
        // `stop()` closes the reading entry, but it does so asynchronously on
        // AudioStreaming's source queue, capturing the player weakly — reassign
        // `player` straight away and that block finds nil and does nothing.
        // Hence the grace period: ask for the teardown, then keep the discarded
        // player alive long enough for the teardown to actually run.
        //
        // Upstream fix: https://github.com/dimitris-c/AudioStreaming/pull/138.
        // Once a release carrying it is pinned in
        // `Packages/PlaybackEngineAudioStreaming/Package.swift`, this reduces
        // back to a bare reassignment.
        let discarded = player
        discarded.stop()
        Task { @MainActor in
            try? await Task.sleep(for: Self.discardedPlayerTeardownGrace)
            withExtendedLifetime(discarded) {}
        }
        player = AudioPlayer()
        player.delegate = self
    }
}

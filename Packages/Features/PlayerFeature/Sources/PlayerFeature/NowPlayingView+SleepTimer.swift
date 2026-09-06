import DesignSystem
import Playback
import SwiftUI

/// The sleep-timer control, split out of ``NowPlayingView``.
///
/// A real seam, not a line-count dodge: everything here is the timer's own
/// menu, label, countdown and VoiceOver value, and none of it is referenced by
/// the rest of the screen beyond the single `sleepTimerButton` the transport
/// row places. Same reasoning as `PlaybackController+Internals` — see
/// `CONTRIBUTING.md` on splitting rather than disabling `type_body_length`.
extension NowPlayingView {
    /// Placed by `transportControls` in `NowPlayingView.swift`, so this one
    /// is internal; everything below it is this file's own business.
    @ViewBuilder
    var sleepTimerButton: some View {
        if let sleepTimer {
            if sleepTimer.isActive {
                // The countdown text and the VoiceOver value now share one
                // clock, so they can't disagree. Mounted only while the timer
                // runs: a 1 Hz TimelineView behind a static moon glyph is a
                // wakeup a second for nothing, which is the same class of
                // background waste the 2026-08-03 power review removed.
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    sleepTimerMenu(sleepTimer, asOf: timeline.date)
                }
            } else {
                sleepTimerMenu(sleepTimer, asOf: .now)
            }
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private func sleepTimerMenu(_ sleepTimer: SleepTimer, asOf date: Date) -> some View {
        Menu {
            if sleepTimer.isActive {
                Button("Cancel Timer", systemImage: "moon.zzz", role: .destructive) {
                    sleepTimer.cancel()
                }
            }
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") {
                    sleepTimer.start(duration: TimeInterval(minutes * 60))
                }
            }
        } label: {
            sleepTimerLabel(sleepTimer, asOf: date)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.glass)
        // Capsule, not circle: the running timer's label carries a countdown
        // and has to be allowed to grow.
        .buttonBorderShape(.capsule)
        // Shares the transport row's namespace, declared on `NowPlayingView`.
        // This is the control the whole change is for: with the button's glass
        // registered in the row's container, the duration menu grows out of the
        // capsule and settles back into it, instead of cross-fading a separate
        // panel over the top of it. The ID has to be stable across the
        // `TimelineView` ticks above — it is, because it doesn't depend on
        // `date` or on whether the timer is running.
        .glassEffectID(TransportGlassID.sleepTimer, in: transportGlass)
        .accessibilityLabel(sleepTimer.isActive ? "Sleep timer running" : "Sleep timer")
        .accessibilityValue(sleepTimerValue(sleepTimer, asOf: date))
    }

    /// How much of the sleep timer is left, for VoiceOver. Until this existed the
    /// remaining time was on screen and nowhere else — the button announced
    /// "sleep timer running" and stopped, so the one number that matters was
    /// available only to people who could read the countdown.
    ///
    /// Minute-granular, and rounded up, on purpose. The visible label ticks every
    /// second; an accessibility value that did the same would make VoiceOver
    /// re-announce a focused button once a second, which is worse than saying
    /// nothing. Rounding up also stops it reporting "0 minutes" while audio is
    /// still playing.
    private func sleepTimerValue(_ sleepTimer: SleepTimer, asOf date: Date) -> Text {
        guard let remaining = sleepTimer.remaining(asOf: date) else {
            // Not localized because it is never spoken: an empty value is
            // omitted by VoiceOver, which is what an idle timer should read as.
            return Text(verbatim: "")
        }
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        return Text("\(minutes) minutes remaining")
    }

    @ViewBuilder
    private func sleepTimerLabel(_ sleepTimer: SleepTimer, asOf date: Date) -> some View {
        if let remaining = sleepTimer.remaining(asOf: date) {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                    .font(.footnote.monospacedDigit())
            }
            .foregroundStyle(.tint)
        } else {
            Image(systemName: "moon.zzz")
                .foregroundStyle(.secondary)
        }
    }
}

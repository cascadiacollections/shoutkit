# Holmdel playback and UX audit — 12 September 2026

> **Resolution:** All eight findings were addressed in the working tree on 12 September 2026.
> Permanent regression coverage is in `PlaybackIntentBoundaryTests.swift`; current validation
> is recorded in `validation.md`. Physical-device and installed-TestFlight checks in the
> acceptance matrix remain release validation because they cannot be established by source.

**Recommendation: fix the pause/cancellation and reset issues before expanding the beta.** The controller has broad unit coverage, but several engine-boundary cases bypass the listener's intent. Passing controller tests alone does not establish reliable audible playback.

## Scope and evidence

- Audited source: `9cd7f0d8929746b2baf3598746a43b872e517839`, initially clean working tree. Project settings identify version **0.5.1 (2)**. These are source settings, not a verified App Store Connect/TestFlight build identity.
- Reviewed the iOS engine, controller and recovery, session handling, metadata/artwork, both system Now Playing implementations, sleep timer, primary player UI, app wiring, directory mapping, Live Activity coordination, EQ/spatial integration, beta configuration, test plan and recorded decisions.
- Existing Playback host suite: **187 tests in 20 suites passed** on Xcode 27.0, build 27A266a.
- Four temporary boundary tests: **all four failed**, producing five failed assertions. They test the desired behavior; failures are audit evidence, not fixes. Source is preserved in `AuditBoundaryTests.swift.txt`, output in `boundary-tests.log`. They were removed from the active test target afterward.
- This is a source and automated-check audit. No TestFlight installation, physical audio output, Bluetooth/AirPlay session, on-device crash payload, accessibility walkthrough or screenshot layout was observed. Findings below distinguish reproduced controller behavior from source-derived engine behavior and layout risks.
- At the initial audit snapshot, no production code had been modified. The resolution above and
  `validation.md` record the production fixes applied afterward.

## Findings, ordered by impact

### 1. P1 — Pause can leave audio running during loading

**Location:** `Packages/Playback/Sources/Playback/PlaybackController.swift:264`, `PlaybackController+Internals.swift:59`.

`output.start` may already have run while controller state remains `.loading`, since the first engine status is asynchronous. The loading branch of `pause()` cancels resolution, publishes `.paused`, and returns without pausing/stopping the output or cancelling its deferred session activation. A task cancellation cannot undo a completed start. The UI can therefore show Play while audio starts or continues after the listener pressed pause. The same method is used by the sleep timer.

**Reproduction:** start a station, let `start` execute without a status callback, then pause. `pauseAfterStartBeforeStatusMustSilenceOutput` fails: neither pause nor stop reaches the output.

**Remedy:** invalidate pending starts and silence any started output on this branch, before publishing the final state. Test activation retries as well as ordinary asynchronous callbacks.

### 2. P1 — Switching stations loses ownership of the previous output before stopping it

**Location:** `Packages/Playback/Sources/Playback/PlaybackController+Internals.swift:20`.

`startPlayback` changes the active station and sets `outputStarted = false` while the old engine keeps playing until the new endpoint resolves. If the listener immediately pauses, the loading branch above never touches the old output. If endpoint resolution fails permanently, `handleResolutionFailure` also leaves that old output running behind the new station's failed state. A switch interrupted while resolving has the same ownership problem.

**Reproduction:** play A and acknowledge playing; select B and pause before its resolution task runs. `switchingThenPausingMustSilencePreviousStation` fails with zero output pause/stop calls.

**Remedy:** preserve truthful ownership during resolution or explicitly stop the previous output before replacing that ownership. Cover failed resolution, interruption and rapid A→B→A switching. This is related to finding 1 but also requires fixing the switch itself.

### 3. P1 — Media-services reset can restart a deliberately paused station

**Location:** `Packages/PlaybackEngineAudioStreaming/Sources/PlaybackEngineAudioStreaming/AudioStreamingPlaybackEngine+Session.swift:311`.

The reset handler uses `didRequestStop == false && currentURL != nil` as its recovery gate. A normal pause leaves both conditions true. After rebuilding the engine, the handler emits a retryable failure; the controller retries even when it was paused. A listener who paused within the ten-minute release window can get unsolicited playback after a reset. This is source-derived; the reset was not triggered on hardware.

**Remedy:** rebuild the audio objects while preserving paused intent and require an explicit play action after reset. Apple's current [media-services reset documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification) specifically says playback should restart only following user action. The recorded decision to recover automatically should be revisited with that guidance and the paused-state case.

**Device reproduction:** play, pause, then use Settings → Developer → Reset Media Services. Repeat during a call, a reconnect, a sleep-timer pause and after Stop. No automatic playback should follow.

### 4. P2 — Permanent stream failures spend the reconnect budget

**Location:** `Packages/Playback/Sources/Playback/PlaybackController+Internals.swift:159`.

Resolution failures honor `PlaybackError.isRetryable`; engine failures always call `attemptReconnect`. An explicitly nonretryable `stationNotAvailable(404)` becomes Connecting and consumes retries instead of showing Unavailable immediately. Default backoff alone adds 2 + 4 + 8 = 14 seconds, plus connection time.

**Reproduction:** `permanentStreamFailureMustNotReconnect` fails both the expected failed state and zero-retries assertion.

**Remedy:** honor the typed retry policy in the engine failure branch after teardown. Separately verify the real dependency's HTTP status mapping; the reproduction supplies the typed error directly.

### 5. P2 — Status callbacks are not tied to playback intent or stream identity

**Location:** `Packages/Playback/Sources/Playback/PlaybackController+Internals.swift:124`; `Packages/PlaybackEngineAudioStreaming/Sources/PlaybackEngineAudioStreaming/AudioStreamingPlaybackEngine.swift:329`.

The controller accepts `.playing`, `.buffering`, failure and EOF against whichever station is currently active. `AudioStatus` has no generation; the engine checks player-object identity, but ordinary station changes reuse that object. A late status can overwrite a user pause or drive recovery for a different station. `audioPlayerDidFinishPlaying` also ignores its entry ID. Metadata has a controller generation guard, but the engine reads the current global generation when the callback arrives, which does not prove which entry produced late metadata.

**Evidence:** `latePlayingAfterPauseMustNotOverrideUserIntent` fails: a supplied late callback changes paused back to playing. This proves controller susceptibility, not a measured frequency of that ordering in AudioStreaming.

**Remedy:** distinguish user intent from engine observations; correlate entry-scoped callbacks with the active request. Add adapter tests for queued state/error/EOF/metadata callbacks across switch, pause and reset.

### 6. P2 — Buffering controls announce the opposite action

**Location:** `Packages/Features/PlayerFeature/Sources/PlayerFeature/MiniPlayerView.swift:95` and `NowPlayingView.swift:269`.

Both controls announce Play for every state except playing. In loading/buffering, tapping actually calls `togglePlayPause()` and pauses/cancels. A VoiceOver listener hears Play but activates silence. Sighted users see only a spinner, so cancellation is also undiscoverable.

**Remedy:** derive the accessible action from the same state mapping as the action: Pause or Cancel connection during loading/buffering, Pause while playing, Play while paused, Retry on failure. Keep a clear cancellation affordance while the spinner is shown. Verify both surfaces with VoiceOver.

### 7. P2 — Full-player layout lacks a compact-height/large-text fallback

**Location:** `Packages/Features/PlayerFeature/Sources/PlayerFeature/NowPlayingView.swift:100`.

The player uses a non-scrolling vertical stack with 272-point artwork (plus its padding), several large gaps, two text blocks, a growing transport control and a route picker. Landscape is explicitly supported by the app. Fixed artwork and controls alone consume most compact landscape height; increasing text grows the contents further. There is no scrolling or alternate arrangement to keep controls reachable.

**Evidence level:** source-derived layout risk, not a rendered clipping measurement.

**Remedy:** provide a compact-height layout or a scrollable arrangement with reachable transport, and size art to available space. Validate small iPhone landscape, all accessibility text sizes, long station/track names, translated strings, and narrow iPad windows.

### 8. P2 — Exhausted stalls look like an ordinary user pause

**Location:** `Packages/Playback/Sources/Playback/PlaybackController+Recovery.swift:68`; `NowPlayingView.swift:217`.

A stall uses a 90-second ceiling per buffering attempt, then retries three times, finally falling back to `.paused`. If each attempt stalls for the full ceiling, that is about **374 seconds** (four × 90 + 14 backoff), excluding resolution time. The final UI removes the status badge and shows the old track/genre in the mini-player without explaining the network stop. The ceiling is a documented battery policy; the UX problem is the silent terminal state and prolonged undifferentiated Connecting message.

**Remedy:** preserve a recoverable stall reason and make Retry explicit. Separate initial connecting from reconnecting. Set timeout targets from measured device results; do not assume six minutes is an acceptable listener experience.

## Additional risks requiring integration/device evidence

| Area | Evidence and next check |
|---|---|
| HLS and unsupported codecs | Directory models recognize HLS; the controller discards endpoint format and always passes the URL to AudioStreaming. The pinned checkout lists direct file/ICY formats and has no HLS/playlist implementation found by source search. Use a known-good HLS fixture and unsupported-codec fixture to verify selection/failure behavior; support routing or visibly filter incompatible stations. Do not treat directory `hidebroken` as engine compatibility. |
| Live edge after pause | The wrapper calls `player.resume()` when paused. Pinned AudioStreaming resumes with `startPlayer(resetBuffers: false)`. This does not implement the controller's documented guarantee of rejoining live edge. Compare against a timestamped broadcast after 30-second and multi-minute pauses; define whether buffered replay is intentional. |
| Headphone route recovery | Route availability resumes a previously route-paused stream without a time limit or matching the old device. Validate reconnecting the same headphones, connecting a different route much later, and route availability during an interruption. Preserve user pause precedence. |
| Reset teardown lifetime | The known timer-deinit mitigation retains the discarded player for one second, rather than awaiting confirmed teardown. It is a recorded workaround, not proof the race is impossible under queue starvation. Stress reset during network retries and review actual crash stacks before attributing a crash to this dependency. |
| EQ, spatial and output gain | Presets can boost bands; no explicit headroom compensation is applied in the EQ wrapper. Measure clipping/loudness on near-full-scale material, toggle both effects during playback, verify mono/stereo behavior and route changes, and measure motion/energy cost while paused. These are measurement questions, not confirmed audible defects. |
| Audible latency | Tap-to-audio trace ends on `.playing`; the gain ramp subsequently fades in over 350 ms. It measures state transition latency, not the first audible sample at speakers/AirPlay. Record actual output timing separately. |
| System Now Playing | iOS 26 uses MediaPlayer and iOS 27 uses MediaSession. Host tests do not execute these iOS surfaces. Test both OS generations, lock-screen commands and Bluetooth art/text together. Live Activity is off by default; only gate release on it if enabled in the shipped beta. |

## Existing strengths

- Production registration is explicitly wired; Playback remains testable behind an output protocol.
- Audio background mode and playback/long-form session policy are present. Session activation failures are surfaced after bounded activation retries.
- Controller tests cover interruption resume policy, pause/stop cancelling reconnect, watchdog recovery, paused release, finite EOF vs looping, metadata parsing and artwork policies.
- Artwork downsampling and asynchronous resource resolution reduce main-thread and memory pressure; generation checks exist for metadata at the controller seam.
- Main transport targets are explicitly sized, text groups have useful accessibility grouping, and the artwork/playing indicator honor accessibility motion settings. The playing indicator pauses when the scene is inactive.
- Broad ATS relaxation has a documented URLSession/HTTP-radio rationale. This audit does not recommend replacing it with a media-only exception that would block the production engine.

## TestFlight acceptance matrix

Run against the actual installed beta after matching version/build and GitCommitSHA to its archive. Keep station URL/format, OS, device, route, network, timestamps and reproduction sequence with each result.

| Scenario | Required outcome |
|---|---|
| Cold launch, HTTP/HTTPS MP3/AAC, ICY and finite content | Audible playback; truthful state; correct EOF behavior; no repeated finite programme unless looping enabled. |
| HLS, Ogg Vorbis, unsupported codec, 404/403, TLS failure, malformed playlist | Supported streams play; unsupported/permanent failures terminate clearly without an endless spinner. |
| Rapid A→B→A and pause during resolution/activation | Latest intent wins; silence after pause; no stale metadata or wrong-station output. |
| Wi-Fi→cellular, tunnel/dropout, airplane mode, restored connectivity | Bounded retries, understandable recovery status, explicit terminal retry, no resurrected playback after pause/stop. |
| Calls answered/declined, alarm, Siri, other media | Expected pause/resume without stealing audio or losing user pause intent. |
| Unplug/reconnect wired headphones, AirPods, car Bluetooth, AirPlay | No unintended speaker playback; correct controls and metadata; no unexpected delayed auto-resume. |
| Locked/background for 30–120 minutes | Stable audio and memory, measured energy, sleep timer fires and stays silent. Test timer expiry while reconnecting too. |
| Pause 30 seconds / 11 minutes; reset while playing/paused/stopped | Defined live-edge behavior, working resume after release, no auto-play following media-services reset. |
| VoiceOver, largest text, Reduce Motion/Transparency, landscape/iPad | Correct action names, reachable controls, readable content and focus order. |
| Upgrade existing beta, offline launch, missing artwork, diagnostics opt-in/out | Favorites/settings survive, usable offline saved content, graceful artwork fallback, reproducible diagnostic export. |

Fix findings 1–3 first, add permanent adapter-level regression coverage, then address recovery messaging and accessibility. A successful unsigned simulator build cannot validate signing, TestFlight distribution, actual audio routing, battery behavior or crash freedom.

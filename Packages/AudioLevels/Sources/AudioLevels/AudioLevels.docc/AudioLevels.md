# ``AudioLevels``

Live per-band audio levels from PCM, and the plug-in protocol a playback engine hands that PCM
through.

## Overview

A leaf module with no dependencies beyond Accelerate and AVFoundation, and nothing specific to
radio or ShoutKit. It suits any `AVAudioEngine` app that wants a meter for what is playing right
now. A waveform view doesn't fit live audio, which has no duration to lay out and no position
to scrub.

An engine owns one tap and fans its buffers out to any number of ``AudioTapPlugin``s through an
``AudioTapPluginSet``:

```swift
let taps = AudioTapPluginSet()
engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [taps] buffer, time in
    taps.dispatch(buffer, at: time)
}
```

``AudioLevelMeter`` is the plug-in that turns those buffers into ``AudioLevels`` frames: 24
log-spaced bands from 40 Hz to 16 kHz, tilted 3 dB per octave, mapped from a −60 dB floor to
`0...1`, and smoothed with a fast attack and slow release:

```swift
guard let meter = AudioLevelMeter() else { return }
taps.add(meter)
meter.onTermination { taps.remove(meter) }
for await frame in meter.levels { draw(frame) }
```

The meter's ``AudioLevelMeter/levels`` stream is handed out once and isn't retained by the
meter. The stream ends when its consumer is cancelled or stops iterating, so detaching in
``AudioLevelMeter/onTermination(_:)`` can't leak a tap.

For drawing, the `AudioLevelsUI` product adds `AudioLevelsView` (bars or a mirrored broadcast
meter with peak caps) and `LiveAudioLevelsView`, which subscribes only while active and eases
to rest when it stops.

The algorithm is specified in `docs/audio-levels-spec.md` in the repository, with golden
vectors this package's tests check. The Holmdel Android client implements the same spec.

## Topics

### Analysis

- ``AudioLevels``
- ``AudioSpectrumAnalyzer``
- ``AudioLevelMeter``
- ``PeakHold``

### Engine plug-ins

- ``AudioTapPlugin``
- ``AudioTapPluginSet``

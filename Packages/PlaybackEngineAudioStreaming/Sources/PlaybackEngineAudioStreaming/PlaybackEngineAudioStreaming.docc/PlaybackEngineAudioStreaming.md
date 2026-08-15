# ``PlaybackEngineAudioStreaming``

The production playback engine: `AVAudioEngine`-backed, with an equalizer and spatial audio.

## Overview

`Playback` deliberately ships no engine, so that adopting it doesn't drag an Ogg/Vorbis codec
stack along. This package is that engine — ``AudioStreamingPlaybackEngine``, a
`RadioPlaybackEngine` built on the
[AudioStreaming](https://github.com/dimitris-c/AudioStreaming) library.

Register it during startup, before the first `PlaybackController` is constructed:

```swift
import PlaybackEngineAudioStreaming

registerProductionPlaybackEngine()
```

Ordering matters: the container registration is `.singleton`-scoped and `PlaybackController`
resolves eagerly, so a controller built before this call holds the stub for the process
lifetime. See "Registering a Playback Engine" in the `Playback` documentation for the full
contract and for the alternative of injecting an engine directly.

### Platforms

iOS only. AudioStreaming pulls the ogg and vorbis binary xcframeworks, which ship no watchOS
slice — and SwiftPM fetches binary artifacts regardless of platform conditions, which is why
this is a separate package rather than a conditional dependency inside `Playback`. The watch app
supplies its own `AVPlayer`-backed engine instead.

### Capabilities

This engine reports `true` for both `supportsEqualizer` and `supportsSpatialAudio`, because an
`AVAudioEngine` render graph is what makes inserting an EQ node and an environment node
possible. Spatial audio here is HRTF binaural virtualization with head tracking, not
object-based audio — a radio stream carries no object metadata to render.

## Topics

### The Engine

- ``AudioStreamingPlaybackEngine``

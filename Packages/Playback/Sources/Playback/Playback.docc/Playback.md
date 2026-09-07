# ``Playback``

Stream a radio station, and keep the rest of the system in step with it.

## Overview

`Playback` owns the state machine for internet-radio playback: what is playing, what the
system's Now Playing surfaces show, and how the app reacts when a stream stalls or an
interruption arrives. It is deliberately incomplete on its own.

**It ships no audio engine.** ``PlaybackController`` drives an ``AudioOutput``, and no
implementation of that protocol lives here — that seam is what keeps this package free of a
codec dependency, so adopting it doesn't drag an Ogg/Vorbis toolchain along. Before playback
can produce sound you must supply an engine. Start with
<doc:RegisteringAPlaybackEngine>; skipping it is the single most common way to end up with an
app that builds, launches, and plays silence.

The other thing worth knowing up front: several of this package's public signatures are written
in `RadioDirectory`'s vocabulary (`Station`, `NowPlayingMetadata`, `RadioDirectoryError`), so
callers generally need `import RadioDirectory` alongside `import Playback`.

## Topics

### Getting Started

- <doc:RegisteringAPlaybackEngine>

### Controlling Playback

- ``PlaybackController``
- ``PlaybackState``
- ``StationPlaybackPhase``
- ``PlaybackError``

### Implementing an Engine

The conformance surface. Implement ``RadioPlaybackEngine`` rather than ``AudioOutput`` directly
unless you have a reason not to — capability probes for the equalizer and spatial audio are
made against the former, so an ``AudioOutput``-only conformance silently reports no support.

- ``RadioPlaybackEngine``
- ``AudioOutput``
- ``AudioStatus``
- ``AudioTrackInfo``
- ``StubRadioPlaybackEngine``

### Track Metadata

- ``ICYMetadataParser``
- ``TrackResources``
- ``HeardTrack``
- ``SongTitleFilter``

### System Integration

- ``NowPlayingPresenting``
- ``NowPlayingArtwork``

### Audio Processing

- ``EqualizerPreset``
- ``EqualizerCurves``

### Supporting Features

- ``SleepTimer``
- ``StationConnectionPrewarmer``

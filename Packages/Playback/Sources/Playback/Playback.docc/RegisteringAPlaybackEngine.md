# Registering a Playback Engine

Give ``PlaybackController`` something that can actually make sound.

## Overview

`Playback` ships no audio engine. ``PlaybackController`` drives an ``AudioOutput``, and every
implementation of that protocol lives outside this package — that is what keeps `Playback` free
of a codec dependency and adoptable on its own.

Until you supply one, `Container.shared.radioPlaybackEngine` resolves to
``StubRadioPlaybackEngine``, whose `start(url:streamGeneration:)` does nothing. The failure mode
is quiet by design and worth recognising:

- the app compiles and links,
- it launches,
- ``PlaybackController/play(_:)`` moves ``PlaybackState`` to `.loading`,
- and it stays there. No audio, no error, no timeout.

There is no build-time error because the container always resolves to *something*; that is what
lets previews, unit tests, and the watch app work without an engine on hand. The stub does log a
fault to the `ShoutKit.Playback` subsystem (category `StubEngine`) the first time `start` is
called, so filtering Console for that subsystem will confirm the diagnosis quickly.

## Registering the production engine

The AudioStreaming-backed engine lives in the `PlaybackEngineAudioStreaming` package. Register
it once, during startup, before any playback can begin:

```swift
import PlaybackEngineAudioStreaming

@main
struct MyRadioApp: App {
    init() {
        registerProductionPlaybackEngine()
    }
    // ...
}
```

Ordering is the part to get right: register before the first ``PlaybackController`` is created.
The iOS-only `PlaybackController.init(directory:)` resolves its engine eagerly through the
container, and the registration is `.singleton`-scoped, so a controller built before
registration holds the stub for the rest of the process — registering afterwards will not
retroactively fix it.

## Injecting an engine directly

If you have your own engine — a different codec stack, an `AVPlayer`-backed one for watchOS, or
a fake in tests — skip the container and use the designated initializer:

```swift
let controller = PlaybackController(
    directory: myDirectory,
    output: MyEngine(),
    nowPlayingCenter: myNowPlayingCenter
)
```

This is how the watch app works, and it is why the stub logs rather than trapping: a no-op
engine reached through this path is legitimate. This initializer is also the only one available
off iOS — `init(directory:)` is gated to `#if os(iOS)` precisely so a tvOS or visionOS target
can't inherit it and silently resolve the stub.

> Important: ``PlaybackController`` takes ownership of the engine's callbacks. Its initializer
> assigns ``AudioOutput/onStatusChange`` and ``AudioOutput/onTrackInfo``, overwriting anything
> you set beforehand. Observe playback through the controller, not by attaching to the engine.

## Implementing your own engine

Conform to ``RadioPlaybackEngine`` rather than ``AudioOutput`` directly. Both will compile, but
the equalizer and spatial-audio capability probes are conditional casts to
``RadioPlaybackEngine`` — an ``AudioOutput``-only conformance silently reports no support for
either, and the corresponding controls degrade to no-ops.

Two contracts are not expressible in the type system, so they are stated here:

**Echo the stream generation.** ``AudioOutput/start(url:streamGeneration:)`` hands you a token.
Every ``AudioTrackInfo`` you emit for that stream must carry the same value back in
``AudioTrackInfo/streamGeneration``. The controller uses it to discard metadata that arrives
late from a stream the listener has already switched away from. `AudioTrackInfo`'s initializer
defaults this parameter to `0`, which means an implementation that ignores it compiles cleanly
and then misattributes track titles across station changes.

**Report status transitions.** Drive ``AudioOutput/onStatusChange`` with ``AudioStatus`` as the
stream progresses. A controller that never sees `.playing` stays in `.loading` indefinitely —
the same visible symptom as having no engine at all.

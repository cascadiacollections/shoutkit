# Audio levels spec

The live level meter on Holmdel's Now Playing screen, specified so every client draws the same
bars from the same audio. The reference implementation is the MIT
[`AudioLevels`](../Packages/AudioLevels) Swift package. The Android client
([shoutkit-android](https://github.com/cascadiacollections/shoutkit-android), `:libs:audio-levels`)
implements the same steps and checks the same golden vectors.

Version: **1** (2026-11-10). Changing any constant below changes the golden vectors. Bump the
version, regenerate the vectors, and update both clients in the same release.

## Pipeline

Each tapped PCM buffer goes through these steps.

1. **Mixdown.** Average all channels to mono. Interleaved and planar layouts give the same
   result.
2. **Framing.** Take the newest `N = 1024` frames. A shorter buffer is zero-padded *at the end*.
3. **Window.** Multiply by a Hann window,
   `w[n] = 0.5 − 0.5·cos(2πn / N)` for `n` in `0..<N`. This is the *periodic* form (denominator
   `N`, not `N − 1`), which is what `vDSP` `.hanningDenormalized` produces. It was checked
   numerically against vDSP.
4. **Transform.** Run a forward complex DFT of the windowed real signal (imaginary input zero),
   then take the magnitude `|X[k]| = √(re² + im²)` for `k` in `0..<N/2`.
5. **Bands.** Use `B = 24` bands, log-spaced from `fmin = 40 Hz` to `fmax = 16 kHz`.
   - Band edge `e` (for `e` in `0...B`) is at `f(e) = fmin · (fmax/fmin)^(e/B)`.
   - Its bin is `bin(e) = clamp(round(f(e) / (sampleRate/N)), 1, N/2)`.
   - Band `b` covers bins `start ..< end`, where `start = min(lower, N/2 − 1)` and
     `end = min(N/2, max(bin(b+1), start + 1))`. `lower` starts at `bin(0)` and becomes `end`
     after each band. Every band has at least one bin.
   - A band's magnitude is the **maximum** `|X[k]|` over its bins.
6. **Scale to dBFS.** `dB = 20·log10(max(peak · 4/N, smallest normal float))`. The `4/N` maps a
   full-scale sine to 0 dBFS: `N/2` for the DFT, then ×2 for the Hann coherent gain.
7. **Tilt.** Add `3 dB × log2(center / 1000 Hz)`, where
   `center = fmin · (fmax/fmin)^((b + 0.5)/B)`. Music falls about 3 dB per octave, and without
   the tilt the top third of the bands sat near zero on real stations.
8. **Normalize.** `level = clamp((dB − floor) / −floor, 0, 1)` with `floor = −60 dB`.

## Ballistics

Published frames are smoothed per band against the previous published frame:

```
next = prev + (raw − prev) × (raw > prev ? 0.7 : 0.18)
```

Publishing is capped at one frame per 33 ms. The tap's own cadence is usually slower: about
100 ms buffers on Apple platforms (4410 frames at 44.1 kHz, measured).

## Drawing (UI)

**Auto-gain.** Before drawing, scale each frame by a reference level, clamping to 1. The
reference jumps up to the frame's loudest band whenever that is higher, and otherwise decays at
0.15 of full scale per second. It never drops below 0.3. Streams differ by 10 dB or more in
mastering, and with a fixed scale KEXP drew as a row of dots on the iOS simulator. Compact
meters fold *after* gain.

Bars and caps are drawn at `level^0.6` of the available height. Typical stations sit between
0.1 and 0.4 per band, which drawn linearly is a few points tall and reads as a dotted line. The
curve keeps 0 at 0 and 1 at 1. It is display only, so the analysis and golden vectors are
unaffected.

## Peak caps (UI)

Each band's cap jumps to any higher level, holds for 600 ms, then falls at 0.9 of full scale per
second until a level catches it. A frame where every band is zero means "at rest" and resets the
caps. The rule is time-based so it behaves the same at any frame rate.

## Compact meters

To show fewer bars (a mini player), fold the 24 bands into `n` groups,
`[g·24/n, max(g·24/n + 1, (g+1)·24/n))`, and take the **maximum** in each. Don't run a second
analysis.

## When to meter

Tap only while something is consuming levels: Now Playing visible, playing, app in the
foreground. Remove the tap when the consumer goes away. Hide the meter entirely when the system
asks for reduced motion, or when the user turns it off in Settings. Don't stop it for low-power
modes. The work is about ten 1024-point transforms a second, and stopping it there made the bars
look broken.

## Golden vectors

[`golden-vectors.json`](../Packages/AudioLevels/Tests/AudioLevelsTests/Resources/golden-vectors.json)
holds the cases. Each case gives `sampleRate`, `frames`, sine `tones` (`frequency`, `amplitude`)
and a `noiseAmplitude`. A client rebuilds the mono input as

```
s[n] = Σ amplitude · sin(2π · frequency · n / sampleRate)  +  noiseAmplitude · u[n]
```

computed in double precision and stored as 32-bit float. `u[n]` comes from the LCG
`x ← (1664525·x + 1013904223) mod 2³²`, seeded with `x = 1`. Advance it once per sample, then
take `u = x / 2³¹ − 1`. Run steps 2–8 (the input is already mono), and every band must be within
`tolerance` (0.01) of `expected`.

`smoothing` gives a single band's raw `inputs`, starting from 0, and the `expected` output of the
ballistics above, to within 1e-4.

To regenerate after an intentional change, from `Packages/AudioLevels`:

```sh
AUDIOLEVELS_WRITE_GOLDEN=$PWD/Tests/AudioLevelsTests/Resources/golden-vectors.json \
  swift test --disable-xctest --filter GoldenVectorTests
```

Then copy the file into the Android module's test resources.

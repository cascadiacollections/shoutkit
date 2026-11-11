import Accelerate
import AVFoundation

/// Turns PCM into per-band levels, exactly as docs/audio-levels-spec.md lays
/// out: a mono mixdown of the newest ``frameSize`` frames, a Hann window, a DFT,
/// the peak magnitude in each log-spaced band, a per-octave tilt, and a decibel
/// floor mapped to `0...1`.
///
/// Not `Sendable` and not thread-safe: it reuses its scratch buffers between
/// calls. ``AudioLevelMeter`` is the thread-safe plug-in that wraps it.
public final class AudioSpectrumAnalyzer {
    /// Spec constants. Changing any of these changes every golden vector.
    public enum Defaults {
        public static let frameSize = 1024
        public static let minimumFrequency: Float = 40
        public static let maximumFrequency: Float = 16000
        public static let floorDecibels: Float = -60
        /// Music carries far more energy low than high — roughly pink, falling
        /// about 3 dB per octave — so an untilted meter shows busy bass and a
        /// near-dead top half. Each band is lifted this many dB per octave above
        /// 1 kHz (and lowered below). Measured on KEXP without it, the top third
        /// of the bands sat at or near zero.
        public static let tiltPerOctave: Float = 3
        public static let tiltPivotFrequency: Float = 1000
    }

    public let frameSize: Int
    public let bandCount: Int

    private let minimumFrequency: Float
    private let maximumFrequency: Float
    private let floorDecibels: Float
    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private let zeros: [Float]
    private let bandTilts: [Float]
    private var samples: [Float]
    private var outputReal: [Float]
    private var outputImaginary: [Float]
    private var bandBins: [Range<Int>] = []
    private var bandBinsSampleRate: Double = 0

    /// Returns `nil` for an invalid configuration, or if Accelerate rejects
    /// `frameSize` — it accepts only `f × 2ⁿ` with `f` in {1, 3, 5, 15}, `n ≥ 3`.
    public init?(
        frameSize: Int = Defaults.frameSize,
        bandCount: Int = AudioLevels.defaultBandCount,
        minimumFrequency: Float = Defaults.minimumFrequency,
        maximumFrequency: Float = Defaults.maximumFrequency,
        floorDecibels: Float = Defaults.floorDecibels,
        tiltPerOctave: Float = Defaults.tiltPerOctave,
    ) {
        guard bandCount > 0, minimumFrequency > 0, maximumFrequency > minimumFrequency, floorDecibels < 0,
              let dft = try? vDSP.DiscreteFourierTransform(
                  count: frameSize,
                  direction: .forward,
                  transformType: .complexComplex,
                  ofType: Float.self,
              ) else { return nil }
        self.frameSize = frameSize
        self.bandCount = bandCount
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency
        self.floorDecibels = floorDecibels
        self.dft = dft
        bandTilts = (0 ..< bandCount).map { band in
            let center = minimumFrequency
                * pow(maximumFrequency / minimumFrequency, (Float(band) + 0.5) / Float(bandCount))
            return tiltPerOctave * log2(center / Defaults.tiltPivotFrequency)
        }
        window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: frameSize,
            isHalfWindow: false,
        )
        zeros = Array(repeating: 0, count: frameSize)
        samples = Array(repeating: 0, count: frameSize)
        outputReal = Array(repeating: 0, count: frameSize)
        outputImaginary = Array(repeating: 0, count: frameSize)
    }

    /// Levels for the newest ``frameSize`` frames of `buffer`, mixed to mono and
    /// zero-padded at the end when it is shorter. `nil` for a buffer this can't
    /// read: anything but `Float32` (interleaved or not), or one with no frames.
    public func levels(for buffer: AVAudioPCMBuffer) -> AudioLevels? {
        guard mixDown(buffer) else { return nil }
        return AudioLevels(bands: bandLevels(sampleRate: buffer.format.sampleRate))
    }

    /// Levels for mono `samples` — the platform-neutral entry point the spec's
    /// golden vectors exercise. Uses the newest ``frameSize`` samples and
    /// zero-pads at the end when there are fewer. `nil` when `samples` is empty
    /// or `sampleRate` isn't positive.
    public func levels(forMono samples: [Float], sampleRate: Double) -> AudioLevels? {
        guard samples.isEmpty == false, sampleRate > 0 else { return nil }
        let used = min(samples.count, frameSize)
        let start = samples.count - used
        for index in 0 ..< frameSize {
            self.samples[index] = index < used ? samples[start + index] : 0
        }
        return AudioLevels(bands: bandLevels(sampleRate: sampleRate))
    }

    private func mixDown(_ buffer: AVAudioPCMBuffer) -> Bool {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0, buffer.format.sampleRate > 0,
              let channels = buffer.floatChannelData else { return false }
        // Interleaved buffers expose one pointer that strides over every
        // channel; deinterleaved ones expose one pointer per channel, stride 1.
        let stride = buffer.stride
        let pointers = buffer.format.isInterleaved
            ? (0 ..< channelCount).map { channels[0] + $0 }
            : (0 ..< channelCount).map { channels[$0] }
        let used = min(frameCount, frameSize)
        let start = frameCount - used
        let scale = 1 / Float(channelCount)
        for index in 0 ..< frameSize {
            guard index < used else {
                samples[index] = 0
                continue
            }
            let frame = (start + index) * stride
            var sum: Float = 0
            for pointer in pointers {
                sum += pointer[frame]
            }
            samples[index] = sum * scale
        }
        return true
    }

    private func bandLevels(sampleRate: Double) -> [Float] {
        if sampleRate != bandBinsSampleRate {
            bandBins = Self.bandBins(
                bandCount: bandCount,
                frameSize: frameSize,
                sampleRate: Float(sampleRate),
                minimumFrequency: minimumFrequency,
                maximumFrequency: maximumFrequency,
            )
            bandBinsSampleRate = sampleRate
        }
        let windowed = vDSP.multiply(samples, window)
        dft.transform(
            inputReal: windowed,
            inputImaginary: zeros,
            outputReal: &outputReal,
            outputImaginary: &outputImaginary,
        )
        // A full-scale sine lands at magnitude N/2 in its bin, halved again by
        // the Hann window's coherent gain — so this maps it to ~1 (0 dBFS).
        let normalization = 4 / Float(frameSize)
        return zip(bandBins, bandTilts).map { bins, tilt in
            var peak: Float = 0
            for bin in bins {
                let real = outputReal[bin]
                let imaginary = outputImaginary[bin]
                peak = max(peak, (real * real + imaginary * imaginary).squareRoot())
            }
            return normalized(decibels: 20 * log10(max(peak * normalization, .leastNormalMagnitude)) + tilt)
        }
    }

    private func normalized(decibels: Float) -> Float {
        min(1, max(0, (decibels - floorDecibels) / -floorDecibels))
    }

    /// DFT bin ranges for `bandCount` log-spaced bands between the two
    /// frequencies. Every band gets at least one bin, so low bands narrower than
    /// a bin still move rather than sitting at zero forever.
    static func bandBins(
        bandCount: Int,
        frameSize: Int,
        sampleRate: Float,
        minimumFrequency: Float,
        maximumFrequency: Float,
    ) -> [Range<Int>] {
        let nyquistBin = frameSize / 2
        let binWidth = sampleRate / Float(frameSize)
        let ratio = maximumFrequency / minimumFrequency
        func bin(atEdge edge: Int) -> Int {
            let frequency = minimumFrequency * pow(ratio, Float(edge) / Float(bandCount))
            return min(nyquistBin, max(1, Int((frequency / binWidth).rounded())))
        }
        var ranges: [Range<Int>] = []
        var lower = bin(atEdge: 0)
        for band in 0 ..< bandCount {
            let start = min(lower, nyquistBin - 1)
            let end = min(nyquistBin, max(bin(atEdge: band + 1), start + 1))
            ranges.append(start ..< end)
            lower = end
        }
        return ranges
    }
}

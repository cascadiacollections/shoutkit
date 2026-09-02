import XCTest
@testable import RustSpike

/// Exercises both FFI variants (UniFFI copy path, raw zero-copy path) against
/// the same known input and asserts they agree with each other and with a
/// hand-computed expected gain. See rust/src/lib.rs for the shared model.
final class CorrectnessTests: XCTestCase {
    private let tolerance: Float = 1e-3

    // samples = 0.1 constant -> RMS = 0.1 -> -20 dBFS; target -14 LUFS -> +6 dB -> 10^(6/20)
    private var expectedGain6dB: Float { pow(10, 6.0 / 20.0) }

    func testUniFFIPathMatchesKnownValue() {
        let samples = [Float](repeating: 0.1, count: 1024)
        let gain = normalizeGain(samples: samples, targetLufs: -14.0)
        XCTAssertEqual(gain, expectedGain6dB, accuracy: tolerance)
    }

    func testRawPathMatchesKnownValue() {
        let samples = [Float](repeating: 0.1, count: 1024)
        let gain = samples.withUnsafeBufferPointer { buf in
            normalizeGainRaw(buf.baseAddress, buf.count, targetLufs: -14.0)
        }
        XCTAssertEqual(gain, expectedGain6dB, accuracy: tolerance)
    }

    func testBothPathsAgreeOnNonConstantInput() {
        let samples = (0..<2048).map { Float(sin(Double($0) * 0.01)) * 0.3 }

        let uniffiGain = normalizeGain(samples: samples, targetLufs: -16.0)
        let rawGain = samples.withUnsafeBufferPointer { buf in
            normalizeGainRaw(buf.baseAddress, buf.count, targetLufs: -16.0)
        }

        XCTAssertEqual(uniffiGain, rawGain, "UniFFI and raw paths must produce identical results")
    }

    func testRawPathGuardsNullAndZeroLength() {
        XCTAssertEqual(normalizeGainRaw(nil, 10, targetLufs: -14.0), 1.0)

        let samples = [Float](repeating: 0.5, count: 4)
        let gain = samples.withUnsafeBufferPointer { buf in
            normalizeGainRaw(buf.baseAddress, 0, targetLufs: -14.0)
        }
        XCTAssertEqual(gain, 1.0)
    }
}

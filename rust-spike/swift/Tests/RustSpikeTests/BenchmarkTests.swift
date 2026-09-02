import XCTest
@testable import RustSpike

/// Benchmarks the UniFFI (per-call copy) path against the raw C-ABI
/// (zero-copy, reused buffer) path for the same DSP function, across a few
/// realistic audio buffer sizes. Run in Release, ideally on a physical device
/// — the copy delta this is trying to measure is easy to underestimate on
/// a simulator (x86_64/Rosetta or Apple Silicon host, not the target ARM core).
///
/// This is a hot loop over an FFI boundary the Swift optimizer cannot see
/// into (each call reaches actual compiled Rust code), so the calls
/// themselves can't be eliminated; `blackhole` additionally forces the
/// compiler to keep every result live.
final class BenchmarkTests: XCTestCase {
    private let iterationCount = 100_000
    private let bufferSizes = [256, 1024, 4096]

    func testCopyVsZeroCopyBenchmark() {
        #if targetEnvironment(simulator)
        let destination = "iOS Simulator (results here understate the real device copy cost)"
        #else
        let destination = "physical device"
        #endif

        print("=== ShoutKit Rust FFI copy vs zero-copy benchmark ===")
        print("destination: \(destination)")
        print("iterations per size: \(iterationCount)")
        print("    size  uniffi ns/call     raw ns/call      delta ns  delta %")

        var blackhole: Float = 0

        for size in bufferSizes {
            let samples = (0..<size).map { Float(sin(Double($0) * 0.001)) * 0.3 }

            let uniffiNs = meanNanoseconds(iterations: iterationCount) {
                blackhole += normalizeGain(samples: samples, targetLufs: -14.0)
            }

            let rawNs = samples.withUnsafeBufferPointer { buf -> Double in
                meanNanoseconds(iterations: iterationCount) {
                    blackhole += normalizeGainRaw(buf.baseAddress, buf.count, targetLufs: -14.0)
                }
            }

            let deltaNs = uniffiNs - rawNs
            let deltaPct = uniffiNs == 0 ? 0 : (deltaNs / uniffiNs) * 100

            print(String(
                format: "%8d  %14.1f  %14.1f  %12.1f  %7.1f%%",
                size, uniffiNs, rawNs, deltaNs, deltaPct
            ))
        }

        // Prevents the whole benchmark from being optimized away as dead code.
        XCTAssertTrue(blackhole.isFinite, "blackhole=\(blackhole)")
    }

    private func meanNanoseconds(iterations: Int, _ body: () -> Void) -> Double {
        let start = DispatchTime.now()
        for _ in 0..<iterations {
            body()
        }
        let end = DispatchTime.now()
        let totalNs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds)
        return totalNs / Double(iterations)
    }
}

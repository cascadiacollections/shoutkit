import shoutkit_rust_spikeFFI

/// Thin Swift-facing wrapper over the raw C-ABI `normalize_gain_raw` export.
/// No copy happens here: `buffer` is whatever pre-allocated memory the caller
/// passed in, and `count` is forwarded as-is to the Rust side.
public func normalizeGainRaw(_ buffer: UnsafePointer<Float>?, _ count: Int, targetLufs: Float) -> Float {
    normalize_gain_raw(buffer, count, targetLufs)
}

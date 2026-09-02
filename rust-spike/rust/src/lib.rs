//! Rust -> Swift FFI toolchain spike (see rust-spike/README.md).
//!
//! One trivial DSP function, exposed two ways, to benchmark copy vs zero-copy FFI:
//!   - `normalize_gain`: UniFFI-friendly, takes an owned `Vec<f32>` (per-call copy).
//!   - `normalize_gain_raw`: raw C ABI, reads a caller-owned buffer in place (zero-copy).
//!
//! The "loudness model" is a simple RMS-to-target-LUFS approximation, not a real
//! EBU R128 implementation - good enough to exercise the pipeline and produce a
//! deterministic, testable gain value.

const MIN_GAIN: f64 = 0.0;
const MAX_GAIN: f64 = 64.0;
const DEFAULT_GAIN: f32 = 1.0;

/// Shared core: both FFI variants funnel through this so their results are
/// guaranteed identical. Never panics - callers may pass silence, NaN targets,
/// or empty buffers, and always get back a finite, clamped gain.
fn gain_for_samples(samples: &[f32], target_lufs: f32) -> f32 {
    if samples.is_empty() {
        return DEFAULT_GAIN;
    }

    let sum_sq: f64 = samples.iter().map(|&s| f64::from(s) * f64::from(s)).sum();
    let rms = (sum_sq / samples.len() as f64).sqrt();

    if !rms.is_finite() || rms <= 0.0 {
        return DEFAULT_GAIN;
    }

    let rms_dbfs = 20.0 * rms.log10();
    let gain_db = f64::from(target_lufs) - rms_dbfs;
    let gain_linear = 10f64.powf(gain_db / 20.0);

    if !gain_linear.is_finite() {
        return DEFAULT_GAIN;
    }

    gain_linear.clamp(MIN_GAIN, MAX_GAIN) as f32
}

/// UniFFI-friendly variant: takes ownership of (a copy of) the sample buffer.
#[uniffi::export]
pub fn normalize_gain(samples: Vec<f32>, target_lufs: f32) -> f32 {
    gain_for_samples(&samples, target_lufs)
}

/// Raw C-ABI, zero-copy variant: reads the caller's buffer in place via
/// `slice::from_raw_parts`. No allocation, never panics.
///
/// # Safety
/// If `ptr` is non-null and `len` is non-zero, the caller must guarantee `ptr`
/// is valid for reads of `len` contiguous, initialized `f32` values for the
/// duration of this call. A null pointer or zero length is always safe and
/// returns the default gain.
///
/// `unsafe` here is a Rust-side marker only - it does not change the
/// `extern "C"` ABI or the exported symbol, so the generated C header still
/// declares a plain `float normalize_gain_raw(...)` and Swift calls it exactly
/// as before.
#[no_mangle]
pub unsafe extern "C" fn normalize_gain_raw(ptr: *const f32, len: usize, target_lufs: f32) -> f32 {
    if ptr.is_null() || len == 0 {
        return DEFAULT_GAIN;
    }
    let samples = unsafe { std::slice::from_raw_parts(ptr, len) };
    gain_for_samples(samples, target_lufs)
}

uniffi::setup_scaffolding!();

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr;

    const TOLERANCE: f32 = 1e-3;

    // samples = 0.1 constant -> RMS = 0.1 -> -20 dBFS; target -14 LUFS -> +6 dB -> 10^(6/20)
    fn expected_gain_6db() -> f32 {
        10f32.powf(6.0 / 20.0)
    }

    #[test]
    fn normalize_gain_matches_known_value() {
        let samples = vec![0.1_f32; 1024];
        let gain = normalize_gain(samples, -14.0);
        assert!(
            (gain - expected_gain_6db()).abs() < TOLERANCE,
            "gain={gain}, expected~{}",
            expected_gain_6db()
        );
    }

    #[test]
    fn normalize_gain_raw_matches_known_value() {
        let samples = vec![0.1_f32; 1024];
        let gain = unsafe { normalize_gain_raw(samples.as_ptr(), samples.len(), -14.0) };
        assert!(
            (gain - expected_gain_6db()).abs() < TOLERANCE,
            "gain={gain}, expected~{}",
            expected_gain_6db()
        );
    }

    #[test]
    fn both_variants_agree_on_nonconstant_input() {
        let samples: Vec<f32> = (0..2048).map(|i| ((i as f32) * 0.01).sin() * 0.3).collect();
        let a = normalize_gain(samples.clone(), -16.0);
        let b = unsafe { normalize_gain_raw(samples.as_ptr(), samples.len(), -16.0) };
        assert_eq!(a, b, "UniFFI and raw paths must produce identical results");
    }

    #[test]
    fn normalize_gain_raw_guards_null_ptr() {
        assert_eq!(
            unsafe { normalize_gain_raw(ptr::null(), 10, -14.0) },
            DEFAULT_GAIN
        );
    }

    #[test]
    fn normalize_gain_raw_guards_zero_len() {
        let samples = [0.5_f32; 4];
        assert_eq!(
            unsafe { normalize_gain_raw(samples.as_ptr(), 0, -14.0) },
            DEFAULT_GAIN
        );
    }

    #[test]
    fn normalize_gain_handles_silence_without_div_by_zero() {
        let samples = vec![0.0_f32; 512];
        assert_eq!(normalize_gain(samples, -14.0), DEFAULT_GAIN);
    }

    #[test]
    fn normalize_gain_handles_empty_buffer() {
        assert_eq!(normalize_gain(Vec::new(), -14.0), DEFAULT_GAIN);
        assert_eq!(
            unsafe { normalize_gain_raw(ptr::null(), 0, -14.0) },
            DEFAULT_GAIN
        );
    }

    #[test]
    fn normalize_gain_guards_nan_target() {
        let samples = vec![0.1_f32; 128];
        let gain = normalize_gain(samples, f32::NAN);
        assert_eq!(gain, DEFAULT_GAIN);
    }

    #[test]
    fn gain_is_clamped_for_near_silent_input() {
        // Extremely quiet input would otherwise demand an enormous gain.
        let samples = vec![1e-9_f32; 256];
        let gain = normalize_gain(samples, -14.0);
        assert!(gain.is_finite());
        assert!(gain <= MAX_GAIN as f32);
    }
}

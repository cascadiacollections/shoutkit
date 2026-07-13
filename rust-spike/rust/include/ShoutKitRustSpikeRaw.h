#pragma once

#include <stddef.h>

// Raw C-ABI, zero-copy variant of the DSP spike function (see rust/src/lib.rs).
// Deliberately NOT routed through UniFFI: callers own and reuse a
// pre-allocated Float buffer and pass it straight through, with no per-call
// copy. Safe to call with a null pointer or zero length (returns 1.0f, the
// default/no-op gain) - never panics on the Rust side.
float normalize_gain_raw(const float *_Nullable ptr, size_t len, float target_lufs);

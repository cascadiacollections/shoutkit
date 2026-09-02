#!/usr/bin/env bash
# Reproducible build for the ShoutKit Rust -> Swift FFI spike:
#   1. cross-compile the Rust staticlib for device + both simulator arches
#   2. lipo the simulator arches into one fat lib
#   3. generate UniFFI Swift bindings + C header/modulemap from a host build
#   4. fold the hand-written raw-FFI header into that modulemap
#   5. package everything into a .xcframework
#
# Requires macOS + Xcode + rustup. This does NOT run on Linux/CI hosts: the
# per-target staticlib compiles fine cross-platform, but `xcodebuild
# -create-xcframework` and the cdylib link step both need an Apple SDK.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$ROOT_DIR/rust"
SWIFT_DIR="$ROOT_DIR/swift"
BUILD_DIR="$ROOT_DIR/build"
CRATE_NAME="shoutkit_rust_spike"

DEVICE_TARGET="aarch64-apple-ios"
SIM_ARM64_TARGET="aarch64-apple-ios-sim"
SIM_X86_64_TARGET="x86_64-apple-ios-sim"

log() { printf '\n>>> %s\n' "$*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: build.sh must run on macOS with Xcode installed (found $(uname -s))." >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Install Xcode and run 'xcode-select --install' / accept the license." >&2
  exit 1
fi
if ! command -v rustup >/dev/null 2>&1; then
  echo "error: rustup not found. Install from https://rustup.rs." >&2
  exit 1
fi

log "Toolchain versions"
rustc --version
cargo --version
xcodebuild -version

log "Ensuring iOS Rust targets are installed"
rustup target add "$DEVICE_TARGET" "$SIM_ARM64_TARGET" "$SIM_X86_64_TARGET"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{bindings,headers,sim-fat}

cd "$RUST_DIR"

log "Building staticlib for device ($DEVICE_TARGET)"
cargo build --release --target "$DEVICE_TARGET" --lib

log "Building staticlib for simulator arm64 ($SIM_ARM64_TARGET)"
cargo build --release --target "$SIM_ARM64_TARGET" --lib

log "Building staticlib for simulator x86_64 ($SIM_X86_64_TARGET)"
cargo build --release --target "$SIM_X86_64_TARGET" --lib

DEVICE_LIB="$RUST_DIR/target/$DEVICE_TARGET/release/lib${CRATE_NAME}.a"
SIM_ARM64_LIB="$RUST_DIR/target/$SIM_ARM64_TARGET/release/lib${CRATE_NAME}.a"
SIM_X86_64_LIB="$RUST_DIR/target/$SIM_X86_64_TARGET/release/lib${CRATE_NAME}.a"
SIM_FAT_LIB="$BUILD_DIR/sim-fat/lib${CRATE_NAME}.a"

log "lipo-ing simulator arches into one fat lib"
lipo -create "$SIM_ARM64_LIB" "$SIM_X86_64_LIB" -output "$SIM_FAT_LIB"
lipo -info "$SIM_FAT_LIB"

log "Building host cdylib to introspect for bindgen"
cargo build --release --lib
HOST_LIB_EXT="dylib"
HOST_LIB="$RUST_DIR/target/release/lib${CRATE_NAME}.${HOST_LIB_EXT}"

log "Generating Swift bindings via uniffi-bindgen"
cargo run --release --bin uniffi-bindgen -- generate \
  --library "$HOST_LIB" \
  --language swift \
  --out-dir "$BUILD_DIR/bindings"

log "Assembling combined header/modulemap for the xcframework"
cp "$BUILD_DIR/bindings/${CRATE_NAME}FFI.h" "$BUILD_DIR/headers/"
cp "$RUST_DIR/include/ShoutKitRustSpikeRaw.h" "$BUILD_DIR/headers/"

MODULEMAP_SRC="$BUILD_DIR/bindings/${CRATE_NAME}FFI.modulemap"
MODULEMAP_DST="$BUILD_DIR/headers/module.modulemap"
# Fold in the raw-FFI header so `import shoutkit_rust_spikeFFI` in Swift sees
# both the UniFFI scaffolding *and* normalize_gain_raw.
awk -v hdr='    header "ShoutKitRustSpikeRaw.h"' '
  /^}/ && !done { print hdr; done=1 }
  { print }
' "$MODULEMAP_SRC" > "$MODULEMAP_DST"

log "Combined modulemap:"
cat "$MODULEMAP_DST"

log "Copying generated Swift bindings into the SPM package"
mkdir -p "$SWIFT_DIR/Sources/RustSpike/Generated"
cp "$BUILD_DIR/bindings/${CRATE_NAME}.swift" "$SWIFT_DIR/Sources/RustSpike/Generated/"

XCFRAMEWORK_PATH="$BUILD_DIR/ShoutKitRustSpike.xcframework"
rm -rf "$XCFRAMEWORK_PATH"

log "Creating XCFramework"
xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" -headers "$BUILD_DIR/headers" \
  -library "$SIM_FAT_LIB" -headers "$BUILD_DIR/headers" \
  -output "$XCFRAMEWORK_PATH"

mkdir -p "$SWIFT_DIR/artifacts"
rm -rf "$SWIFT_DIR/artifacts/ShoutKitRustSpike.xcframework"
cp -R "$XCFRAMEWORK_PATH" "$SWIFT_DIR/artifacts/"

log "Done"
echo "xcframework: $XCFRAMEWORK_PATH"
echo "SPM copy:    $SWIFT_DIR/artifacts/ShoutKitRustSpike.xcframework"
echo
echo "Next: cd swift && xcodebuild test -scheme RustSpike -destination 'platform=iOS Simulator,name=iPhone 16'"

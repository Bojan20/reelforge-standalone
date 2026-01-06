#!/bin/bash
# ReelForge Development Runner
# Builds Rust library and runs Flutter app with native FFI

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
RUST_LIB="$PROJECT_ROOT/target/release/librf_bridge.dylib"
FLUTTER_DIR="$PROJECT_ROOT/flutter_ui"
APP_BUNDLE="$FLUTTER_DIR/build/macos/Build/Products/Debug/reelforge_ui.app"

echo "=== ReelForge Development Build ==="
echo "Project root: $PROJECT_ROOT"

# Build Rust library
echo ""
echo ">>> Building Rust library..."
cd "$PROJECT_ROOT"
cargo build --release -p rf-bridge 2>&1 | tail -5

if [ ! -f "$RUST_LIB" ]; then
    echo "ERROR: Rust library not found at $RUST_LIB"
    exit 1
fi
echo ">>> Rust library built: $RUST_LIB"

# Build Flutter app (creates app bundle)
echo ""
echo ">>> Building Flutter app..."
cd "$FLUTTER_DIR"
flutter build macos --debug 2>&1 | tail -10

if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: App bundle not found at $APP_BUNDLE"
    exit 1
fi

# Copy dylib to app bundle Frameworks
echo ""
echo ">>> Copying native library to app bundle..."
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
cp "$RUST_LIB" "$FRAMEWORKS_DIR/"
echo ">>> Copied to: $FRAMEWORKS_DIR/librf_bridge.dylib"

# Fix library loading path (set rpath)
echo ""
echo ">>> Fixing library install name..."
install_name_tool -id "@rpath/librf_bridge.dylib" "$FRAMEWORKS_DIR/librf_bridge.dylib" 2>/dev/null || true

# Sign the dylib for macOS code signature validation
echo ""
echo ">>> Signing native library..."
codesign --force --sign - "$FRAMEWORKS_DIR/librf_bridge.dylib"
echo ">>> Library signed"

# Re-sign the entire app bundle to include the new dylib
echo ""
echo ">>> Re-signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"
echo ">>> App bundle signed"

# Run Flutter app directly to see stderr output
echo ""
echo ">>> Launching ReelForge (direct)..."
echo ""
"$APP_BUNDLE/Contents/MacOS/reelforge_ui"

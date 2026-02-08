#!/bin/bash
# FluxForge Studio - macOS Build & Run Script
# Handles ExFAT external drive builds by using internal disk for derived data

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_UI="$PROJECT_ROOT/flutter_ui"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/FluxForge-macos"

echo "=== FluxForge Studio - macOS Build ==="
echo "Project: $PROJECT_ROOT"
echo "Derived Data: $DERIVED_DATA"
echo ""

# Parse arguments
CLEAN=false
RUN_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN=true
            shift
            ;;
        --run-only)
            RUN_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--clean] [--run-only]"
            exit 1
            ;;
    esac
done

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning previous build..."
    rm -rf "$DERIVED_DATA" 2>/dev/null || true
    cd "$FLUTTER_UI" && flutter clean 2>/dev/null || true
fi

if [ "$RUN_ONLY" = false ]; then
    echo "Getting dependencies..."
    cd "$FLUTTER_UI" && flutter pub get

    echo ""
    echo "Cleaning AppleDouble files from entire project..."
    "$PROJECT_ROOT/scripts/clean-appledouble.sh" --quiet

    echo ""
    echo "Running pod install..."
    cd "$FLUTTER_UI/macos" && pod install

    echo ""
    echo "Building with xcodebuild (derived data on internal disk)..."
    xcodebuild -workspace "$FLUTTER_UI/macos/Runner.xcworkspace" \
        -scheme Runner \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA" \
        build

    echo ""
    echo "Copying native libraries to app bundle..."
    FRAMEWORKS_DIR="$DERIVED_DATA/Build/Products/Debug/FluxForge Studio.app/Contents/Frameworks"

    # Copy librf_bridge.dylib
    DYLIB_BRIDGE="$PROJECT_ROOT/target/release/librf_bridge.dylib"
    if [ -f "$DYLIB_BRIDGE" ]; then
        cp "$DYLIB_BRIDGE" "$FRAMEWORKS_DIR/"
        echo "✓ Copied librf_bridge.dylib"
    else
        echo "⚠ WARNING: librf_bridge.dylib not found at $DYLIB_BRIDGE"
        echo "  Run 'cargo build --release' first"
    fi

    # Copy librf_engine.dylib (CRITICAL for audio playback!)
    DYLIB_ENGINE="$PROJECT_ROOT/target/release/librf_engine.dylib"
    if [ -f "$DYLIB_ENGINE" ]; then
        cp "$DYLIB_ENGINE" "$FRAMEWORKS_DIR/"
        echo "✓ Copied librf_engine.dylib"
    else
        echo "⚠ WARNING: librf_engine.dylib not found at $DYLIB_ENGINE"
        echo "  Run 'cargo build --release' first"
    fi

    # Verify both exist in app bundle
    echo ""
    echo "Verifying app bundle Frameworks:"
    ls -la "$FRAMEWORKS_DIR/"*.dylib 2>/dev/null || echo "No dylibs found!"

    echo ""
    echo "Build completed!"
fi

echo ""
echo "Launching FluxForge Studio..."
APP_PATH="$DERIVED_DATA/Build/Products/Debug/FluxForge Studio.app"
open "$APP_PATH"

echo "Done!"

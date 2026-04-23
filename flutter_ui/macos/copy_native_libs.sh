#!/bin/bash
# Copy native libraries to macOS app bundle
# This script is called during the Xcode build phase

set -e

echo "=== Copying native libraries to app bundle ==="

# Paths
PROJECT_ROOT="${SRCROOT}/../.."
DYLIB_SOURCE="${PROJECT_ROOT}/target/release/librf_bridge.dylib"
FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"

# Check if dylib exists
if [ ! -f "$DYLIB_SOURCE" ]; then
    echo "WARNING: librf_bridge.dylib not found at $DYLIB_SOURCE"
    echo "Run 'cargo build --release -p rf-bridge' first"
    exit 0
fi

# Create Frameworks directory if needed
mkdir -p "$FRAMEWORKS_DIR"

# Copy main dylib
echo "Copying librf_bridge.dylib..."
cp "$DYLIB_SOURCE" "$FRAMEWORKS_DIR/"

# Copy homebrew dependencies — BUG#15 FIX: dynamic paths via brew --prefix
FLAC_LIB="$(brew --prefix flac 2>/dev/null)/lib/libFLAC.14.dylib"
OGG_LIB="$(brew --prefix libogg 2>/dev/null)/lib/libogg.0.dylib"

if [ -f "$FLAC_LIB" ]; then
    echo "Copying libFLAC.14.dylib..."
    cp "$FLAC_LIB" "$FRAMEWORKS_DIR/"
fi

if [ -f "$OGG_LIB" ]; then
    echo "Copying libogg.0.dylib..."
    cp "$OGG_LIB" "$FRAMEWORKS_DIR/"
fi

# Fix library paths using install_name_tool
echo "Fixing library paths..."

# BUG#15 FIX: Detect actual library paths from binary via otool instead of hardcoding.
# This handles both /opt/homebrew (ARM) and /usr/local (Intel) homebrew installs.

# Fix librf_bridge.dylib — patch any absolute FLAC reference to @executable_path
FLAC_REF=$(otool -L "$FRAMEWORKS_DIR/librf_bridge.dylib" 2>/dev/null | grep -o '/.*libFLAC[^ ]*' | head -1)
if [ -n "$FLAC_REF" ]; then
    install_name_tool -change \
        "$FLAC_REF" \
        @executable_path/../Frameworks/libFLAC.14.dylib \
        "$FRAMEWORKS_DIR/librf_bridge.dylib" 2>/dev/null || true
fi

install_name_tool -id \
    @executable_path/../Frameworks/librf_bridge.dylib \
    "$FRAMEWORKS_DIR/librf_bridge.dylib" 2>/dev/null || true

# Fix libFLAC.14.dylib — patch any absolute OGG reference
if [ -f "$FRAMEWORKS_DIR/libFLAC.14.dylib" ]; then
    OGG_REF=$(otool -L "$FRAMEWORKS_DIR/libFLAC.14.dylib" 2>/dev/null | grep -o '/.*libogg[^ ]*' | head -1)
    if [ -n "$OGG_REF" ]; then
        install_name_tool -change \
            "$OGG_REF" \
            @executable_path/../Frameworks/libogg.0.dylib \
            "$FRAMEWORKS_DIR/libFLAC.14.dylib" 2>/dev/null || true
    fi

    install_name_tool -id \
        @executable_path/../Frameworks/libFLAC.14.dylib \
        "$FRAMEWORKS_DIR/libFLAC.14.dylib" 2>/dev/null || true
fi

# Fix libogg.0.dylib
if [ -f "$FRAMEWORKS_DIR/libogg.0.dylib" ]; then
    install_name_tool -id \
        @executable_path/../Frameworks/libogg.0.dylib \
        "$FRAMEWORKS_DIR/libogg.0.dylib" 2>/dev/null || true
fi

# Sign libraries (required for macOS)
if [ -n "$CODE_SIGN_IDENTITY" ]; then
    echo "Signing libraries..."
    codesign --force --sign "$CODE_SIGN_IDENTITY" "$FRAMEWORKS_DIR/librf_bridge.dylib" 2>/dev/null || true
    codesign --force --sign "$CODE_SIGN_IDENTITY" "$FRAMEWORKS_DIR/libFLAC.14.dylib" 2>/dev/null || true
    codesign --force --sign "$CODE_SIGN_IDENTITY" "$FRAMEWORKS_DIR/libogg.0.dylib" 2>/dev/null || true
fi

echo "=== Native libraries copied successfully ==="

#!/bin/bash
# Bundle all dylib dependencies into macOS app

set -e

APP_BUNDLE="flutter_ui/build/macos/Build/Products/Release/reelforge_ui.app"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
LIB_PATH="target/release/librf_bridge.dylib"

echo "🔧 Bundling dylibs into $APP_BUNDLE"

# Copy main library
cp "$LIB_PATH" "$FRAMEWORKS_DIR/"

# Function to copy dylib and fix its dependencies recursively
bundle_dylib() {
    local dylib_path="$1"
    local dylib_name=$(basename "$dylib_path")

    # Skip if already in Frameworks
    if [ -f "$FRAMEWORKS_DIR/$dylib_name" ] && [ "$dylib_name" != "librf_bridge.dylib" ]; then
        return
    fi

    # Copy dylib
    if [ ! -f "$FRAMEWORKS_DIR/$dylib_name" ]; then
        echo "  📦 Copying $dylib_name"
        cp "$dylib_path" "$FRAMEWORKS_DIR/"
    fi

    # Get all homebrew dependencies
    local deps=$(otool -L "$dylib_path" | grep -E "/opt/homebrew|/usr/local" | awk '{print $1}')

    for dep in $deps; do
        local dep_name=$(basename "$dep")

        # Fix rpath in current dylib
        echo "    🔗 Fixing $dylib_name -> $dep_name"
        install_name_tool -change "$dep" "@rpath/$dep_name" "$FRAMEWORKS_DIR/$dylib_name" 2>/dev/null || true

        # Recursively bundle dependency
        if [ -f "$dep" ]; then
            bundle_dylib "$dep"
        fi
    done
}

# Bundle librf_bridge and all its dependencies recursively
bundle_dylib "$LIB_PATH"

echo "✅ All dylibs bundled successfully"

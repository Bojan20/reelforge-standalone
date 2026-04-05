#!/usr/bin/env bash
set -e
APP_BUNDLE="flutter_ui/build/macos/Build/Products/Release/reelforge_ui.app"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
LIB_PATH="target/release/librf_bridge.dylib"
echo "🔧 Bundling dylibs..."
cp "$LIB_PATH" "$FRAMEWORKS_DIR/"
PROCESSED_FILE=$(mktemp)
trap "rm -f $PROCESSED_FILE" EXIT
bundle_dylib() {
    local dylib_path="$1"
    local dylib_name=$(basename "$dylib_path")
    if grep -q "^$dylib_name$" "$PROCESSED_FILE" 2>/dev/null; then return; fi
    echo "$dylib_name" >> "$PROCESSED_FILE"
    if [ ! -f "$FRAMEWORKS_DIR/$dylib_name" ]; then
        echo "  📦 $dylib_name"
        cp "$dylib_path" "$FRAMEWORKS_DIR/"
    fi
    install_name_tool -id "@rpath/$dylib_name" "$FRAMEWORKS_DIR/$dylib_name" 2>/dev/null || true
    local deps=$(otool -L "$dylib_path" | grep -E "/opt/homebrew|/usr/local" | awk '{print $1}')
    for dep in $deps; do
        local dep_name=$(basename "$dep")
        install_name_tool -change "$dep" "@rpath/$dep_name" "$FRAMEWORKS_DIR/$dylib_name" 2>/dev/null || true
        if [ -f "$dep" ]; then bundle_dylib "$dep"; fi
    done
}
bundle_dylib "$LIB_PATH"
for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    if [ -f "$dylib" ]; then codesign --force --sign - "$dylib" 2>/dev/null || true; fi
done
echo "✅ Done"

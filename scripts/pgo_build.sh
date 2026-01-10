#!/usr/bin/env bash
set -e

# Profile-Guided Optimization (PGO) Build Script
# Expected gain: 10-20% runtime improvement for DSP hot paths

echo "🔧 PGO Build Process"
echo "===================="

PGO_DATA_DIR="/tmp/pgo-data"
mkdir -p "$PGO_DATA_DIR"

# Step 1: Build with profiling enabled
echo ""
echo "📊 Step 1: Building with profiling instrumentation..."
RUSTFLAGS="-C profile-generate=$PGO_DATA_DIR" cargo build --release --profile release-pgo-gen

# Step 2: Run representative workload
echo ""
echo "🎵 Step 2: Running representative audio workload..."
echo "   (This collects profiling data for hot paths)"
echo ""
echo "   Please run the following commands manually:"
echo "   1. cd flutter_ui && flutter run -d macos --release"
echo "   2. Load a project with audio"
echo "   3. Play audio for 20-30 minutes (various operations)"
echo "   4. Export/bounce a project"
echo "   5. Close the app"
echo ""
read -p "Press ENTER when done with profiling run..."

# Step 3: Merge profiling data
echo ""
echo "🔀 Step 3: Merging profiling data..."
if [ -z "$(ls -A $PGO_DATA_DIR/*.profraw 2>/dev/null)" ]; then
    echo "❌ Error: No profiling data found in $PGO_DATA_DIR"
    echo "   Make sure you ran the app and processed audio."
    exit 1
fi

llvm-profdata merge -o "$PGO_DATA_DIR/merged.profdata" "$PGO_DATA_DIR"/*.profraw
echo "✅ Merged $(ls $PGO_DATA_DIR/*.profraw | wc -l | tr -d ' ') profiling files"

# Step 4: Rebuild with PGO data
echo ""
echo "🚀 Step 4: Building optimized binary with PGO..."
RUSTFLAGS="-C profile-use=$PGO_DATA_DIR/merged.profdata -C llvm-args=-pgo-warn-missing-function" \
    cargo build --release --profile release-pgo-use

echo ""
echo "✅ PGO build complete!"
echo ""
echo "Binary location: target/release-pgo-use/librf_bridge.dylib"
echo "Expected gain: 10-20% faster DSP processing"
echo ""
echo "Next steps:"
echo "  1. Test the PGO-optimized binary"
echo "  2. Benchmark against baseline (cargo bench)"
echo "  3. If satisfied, copy to release target"

# Cleanup profiling data (optional)
echo ""
read -p "Delete profiling data? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$PGO_DATA_DIR"
    echo "✅ Profiling data deleted"
fi

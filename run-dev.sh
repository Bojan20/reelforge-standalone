#!/bin/bash
# ReelForge Dev Runner - Flutter + Rust

cd "$(dirname "$0")"

case "$1" in
    flutter|f)
        echo "🎹 Starting Flutter UI..."
        cd flutter_ui
        flutter run -d macos
        ;;
    bridge|b)
        echo "🔗 Generating Rust bridge..."
        cd flutter_ui
        flutter_rust_bridge_codegen generate
        ;;
    rust|r)
        echo "🦀 Building Rust libraries..."
        cargo build --release -p rf-bridge
        ;;
    all|a)
        echo "🚀 Full build: Rust + Bridge + Flutter..."
        cargo build --release -p rf-bridge
        cd flutter_ui
        flutter_rust_bridge_codegen generate
        flutter run -d macos
        ;;
    clean|c)
        echo "🧹 Cleaning..."
        cargo clean
        cd flutter_ui && flutter clean
        ;;
    *)
        echo "ReelForge Dev Commands:"
        echo "  ./run-dev.sh          - Run Flutter app (default)"
        echo "  ./run-dev.sh flutter  - Run Flutter app"
        echo "  ./run-dev.sh bridge   - Regenerate Rust bridge"
        echo "  ./run-dev.sh rust     - Build Rust libraries"
        echo "  ./run-dev.sh all      - Full rebuild + run"
        echo "  ./run-dev.sh clean    - Clean all builds"
        echo ""
        echo "Starting Flutter..."
        cd flutter_ui
        flutter run -d macos
        ;;
esac

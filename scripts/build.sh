#!/bin/bash
# ReelForge Build Script
# Builds Rust library and Flutter app

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== ReelForge Build Script ==="

# Build Rust library first
echo "[1/2] Building Rust library..."
cd "$PROJECT_ROOT"
cargo build --release -p rf-bridge

# Build Flutter app
echo "[2/2] Building Flutter app..."
cd "$PROJECT_ROOT/flutter_ui"
flutter build macos --release

echo "=== Build Complete ==="
echo "App: $PROJECT_ROOT/flutter_ui/build/macos/Build/Products/Release/reelforge_ui.app"

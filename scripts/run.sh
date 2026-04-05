#!/bin/bash
# ReelForge Flutter Run Script
# Auto-kills previous instances before starting new build

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FLUTTER_DIR="$PROJECT_ROOT/flutter_ui"

echo "=== ReelForge Run Script ==="

# Kill any existing flutter run processes
echo "[1/3] Killing previous flutter processes..."
pkill -f "flutter run" 2>/dev/null || true
pkill -f "Flutter Debug" 2>/dev/null || true
pkill -f "reelforge_ui" 2>/dev/null || true
sleep 1

# Clean build if requested
if [[ "$1" == "--clean" ]]; then
    echo "[2/3] Cleaning build..."
    cd "$FLUTTER_DIR"
    flutter clean
    flutter pub get
else
    echo "[2/3] Skipping clean (use --clean for fresh build)"
fi

# Run flutter
echo "[3/3] Starting Flutter..."
cd "$FLUTTER_DIR"
flutter run -d macos


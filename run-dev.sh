#!/bin/bash
# ReelForge Dev Runner
# Pokreće frontend i Tauri backend zajedno

cd "$(dirname "$0")"

# Kill existing processes on exit
cleanup() {
    echo "Stopping..."
    kill $FRONTEND_PID 2>/dev/null
    exit
}
trap cleanup INT TERM

# Start frontend
echo "Starting frontend..."
cd frontend
npm run dev &
FRONTEND_PID=$!
cd ..

# Wait for frontend to start
echo "Waiting for frontend (localhost:5173)..."
sleep 3

# Start Tauri
echo "Starting Tauri..."
cargo run -p reelforge-app

cleanup

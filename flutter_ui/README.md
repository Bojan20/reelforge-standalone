# FluxForge Studio — Flutter UI

Flutter desktop frontend for FluxForge Studio DAW.

## Build

See `CLAUDE.md` in the project root for the full build procedure (xcodebuild flow, NOT `flutter run`).

## Architecture

- **State management:** GetIt (singleton services) + Provider (widget tree reactivity)
- **FFI:** flutter_rust_bridge → `rf-bridge` Rust crate (`librf_bridge.dylib`)
- **Screens:** DAW (engine_connected_layout), SlotLab, Welcome, Settings
- **Shaders:** `shaders/spectrum.frag`, `shaders/anticipation_glow.frag` (Skia fragment shaders)

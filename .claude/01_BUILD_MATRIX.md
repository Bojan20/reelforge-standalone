# FluxForge Studio — Build & Execution Matrix

Claude must always use the correct toolchain for the active subsystem.

**Last Updated:** 2026-01-29

---

## Build Status Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Rust Engine | ✅ Production | All P0-P4 complete |
| Flutter UI | ✅ Production | All panels connected |
| FFI Bridge | ✅ Production | 300+ FFI functions |
| WASM Port | ✅ Production | ~100KB gzipped |
| CI/CD | ✅ Active | 12 jobs, 39 tests |

---

## Rust Engine & DSP

Used for:
- audio engine
- routing
- waveform cache
- DSP (biquad, dynamics, fades, automation)

Commands:

```bash
cargo build --release
cargo test
cargo clippy
```

Rules:
- All engine changes must compile.
- DSP changes must not allocate in audio thread.
- SIMD paths must have scalar fallback.

---

## Flutter UI

Used for:
- timeline UI
- sample editor
- clip editor
- routing panels
- inspector UI

Commands:

```bash
cd flutter_ui
flutter analyze
flutter run
```

Rules:
- No blocking calls in UI thread.
- Waveform data must be batched.
- Zoom and pan must remain 60 FPS.

---

## Cross-Boundary (FFI)

When modifying Rust <-> Flutter boundary:

- Update FFI in `ffi.rs`
- Update bindings in `native_ffi.dart`
- Add safe wrappers in `engine_api.dart`
- Validate memory ownership

Rules:
- Never pass raw pointers without capacity
- Batch large data (waveform, markers)
- Never block audio thread via FFI

---

Claude must always choose the correct matrix before implementing.

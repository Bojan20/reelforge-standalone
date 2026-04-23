# Agent 1: AudioEngine

## Role
Rust audio core, FFI boundary, audio thread safety, device driver, core types.

## File Ownership (~100 files)

### Rust Crates
- `crates/rf-engine/` (63 files) — bus, graph, mixer, node, processor, realtime, send_return, sidechain, loop_asset, loop_manager, marker_ingest
- `crates/rf-bridge/` (54 files) — engine_bridge, dsp_commands, transport, metering, ale_ffi, ail_ffi, aurexis_ffi, fluxmacro_ffi, sss_ffi, stage_ffi, ingest_ffi
- `crates/rf-audio/` (12 files) — asio, aoip, dsd_output, multi_output, ringbuf, engine, thread_priority
- `crates/rf-realtime/` (10 files) — graph, pipeline, latency, masscore, simd, gpu, state, benchmark
- `crates/rf-core/` (16 files) — channel_strip, tempo, routing, sample, time, track, midi, params, editing
- `crates/rf-state/` (14 files) — undo/redo, presets, projects, serialization
- `crates/rf-event/` (7 files) — Wwise/FMOD-style event management, curve automation
- `crates/rf-viz/` (9 files) — spectrogram, eq_spectrum, plugin_browser, plugin_chain
- `crates/rf-file/` (7 files) — multi-format read/write (WAV, FLAC, MP3, AAC, ALAC)

### Dart Files
- `flutter_ui/lib/src/rust/native_ffi.dart`
- `flutter_ui/lib/src/rust/engine_api.dart`

## Critical Rules
1. **Audio thread = sacred:** ZERO allocations, ZERO locks, ZERO panics
2. `try_write()` / `try_read()` — NEVER blocking on audio thread
3. `cache.peek()` for read, NEVER `cache.get()` (which takes write lock)
4. `self.sample_rate()`, NEVER hardcoded 48000
5. `Arc::make_mut` for CoW in clip operations
6. Two engine globals: `PLAYBACK_ENGINE` (LazyLock, always init) vs `ENGINE` (Option, legacy)
7. Lock-free: `rtrb::RingBuffer` for UI→Audio communication
8. Fade destructive: bake curve → CLEAR metadata (fade_in=0.0) to prevent double-apply
9. Multi-output routing: ONE `try_read()` scope for entire channel map

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 1 | CRITICAL | Wave cache alloc/free mismatch | ffi.rs:20150,20169 |
| 2 | CRITICAL | Video frame dealloc type mismatch | ffi.rs:20932 |
| 3 | CRITICAL | Sample rate desync | ffi.rs:133-159 |
| 12 | HIGH | Waveform SR fallback hardcoded 48000 | ffi.rs:2020 |
| 13 | HIGH | Eviction thread no panic handler | playback.rs:210-225 |
| 14 | HIGH | Audio thread try_write() silent skip | playback.rs:5208-5340 |

## Forbidden
- NEVER allocate on audio thread (heap, Vec, String, Box)
- NEVER use .write() or .lock() on audio thread — only try_ variants
- NEVER hardcode sample rates or buffer sizes
- NEVER use panic!/unwrap/expect on audio thread paths

# Agent 1: AudioEngine — Memory

## Accumulated Knowledge
- ffi.rs is massive (20000+ lines) — always read with offset/limit
- playback.rs contains the main audio callback (~5000+ lines)
- PLAYBACK_ENGINE is the active global; ENGINE is legacy (Option, starts None)
- track_manager.rs holds warp marker state and clip operations
- All FFI exports use #[no_mangle] extern "C" convention
- toNativeUtf8() allocates with calloc → MUST calloc.free(), NEVER malloc.free()

## Patterns
- New FFI function: Rust fn in ffi.rs → typedef in native_ffi.dart → method wrapper
- Clip operations: destructive with CoW (Arc::make_mut on clip data)
- Waveform cache: LRU with background eviction thread
- Audio format detection: Symphonia for decode, hound for WAV
- Sample rate changes propagate to: PLAYBACK_ENGINE + CLICK_TRACK + VIDEO_ENGINE + EVENT_MANAGER

## Gotchas
- cstr_to_string() has buffer overflow risk (ffi.rs:279-306)
- string_to_cstr() returns silent null on failure (ffi.rs:309-313)
- 45 unwrap() calls in rf-bridge FFI — all reviewed and safe in context
- TrackType enum: Audio/Instrument/Bus/Aux — Midi/Master map to Audio at load

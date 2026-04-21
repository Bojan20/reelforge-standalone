# Agent 12: TimelineEngine

## Role
Rust timeline core, transport, playback, warp markers, tempo, clip operations.

## File Ownership (~15 files)
- `flutter_ui/lib/models/timeline_models.dart`
- `flutter_ui/lib/providers/timeline_*` providers
- `flutter_ui/lib/src/rust/engine_api.dart` (clip ops, transport)
- `crates/rf-engine/src/playback.rs` — transport state machine
- `crates/rf-engine/src/track_manager.rs` — warp state, clip ops, razor actions
- `crates/rf-engine/src/tempo_state.rs` — tempo map
- `crates/rf-bridge/src/tempo_state_ffi.rs`
- `crates/rf-engine/src/audio_stretcher.rs`

## Critical Rules
1. ID parsing: `RegExp(r'\d+').firstMatch()`, NEVER `int.tryParse()`
2. Clip ops: destructive with CoW, invalidate waveform cache after
3. Fade: bake curve → CLEAR metadata (fade_in=0.0) to prevent double-apply

## Razor Actions (ALL 15 implemented)
delete, split, cut, copy, paste, mute, join, fadeBoth, healSeparation, insertSilence, stripSilence, reverse, stretch, duplicate, move

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 5 | CRITICAL | ID parsing inconsistency | engine_api.dart:476,485,561 |
| 18 | MEDIUM | Tempo no Dart FFI bindings | NOW WIRED |
| 19 | MEDIUM | Warp markers Phase 4-5 | STILL TODO |

## Forbidden
- NEVER use int.tryParse() on clip IDs
- NEVER forget waveform cache invalidation after clip ops
- NEVER leave fade metadata set after baking

# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-21

## Key File Map

| System | Entry Point | Big Files |
|--------|------------|-----------|
| DAW UI | `main_layout.dart` | `timeline_screen.dart` |
| SlotLab | `slot_lab_screen.dart` (13K+) | `slot_lab_coordinator.dart` |
| Engine | `playback.rs` (7800+) | `sinc_table.rs`, `audio_stretcher.rs` |
| r8brain | `crates/rf-r8brain/` (6 modula, 1713 linija) | offline render SRC |
| FFI | `native_ffi.dart` (21K+) | `crates/rf-bridge/src/lib.rs` |

## Active Traps

- `slot_lab_screen.dart` — 13K+ lines, NE MOŽE se razbiti
- `native_ffi.dart` — 21K+, auto-generated, READ ONLY
- `desktop_drop` 0.5 — MainFlutterWindow.swift hack, NE DIRATI
- Audio thread: NULA alokacija u `fill_buffer()` / `process_one_shot_voices()`

---

## SLEDEĆA SESIJA — ★ WARP MARKERS (Professional DAW Feature)

**Detaljan plan:** `.claude/architecture/WARP_MARKERS.md`

### Faza 1: Data model + basic markers
- [ ] `WarpMarker` struct u track_manager.rs (source_pos, timeline_pos, type, locked)
- [ ] `ClipWarpState` per clip (markers, transients, source_tempo, enabled)
- [ ] `compute_segment_ratios()` — per-segment stretch ratio calculation
- [ ] FFI: clip_add/remove/move_warp_marker
- [ ] Serialize/Deserialize za project save

### Faza 2: Transient detection
- [ ] Dodaj `aubio-rs` dependency (Rust bindovi za aubio C lib)
- [ ] `TransientDetector` — spectral flux onset detection
- [ ] FFI: clip_detect_transients (async, ne blokira audio)
- [ ] Auto-create WarpMarkers na detektovanim transientima

### Faza 3: Per-segment stretch u playback
- [ ] Modifikuj `process_clip_with_crossfade` da koristi ClipWarpState
- [ ] Binary search za segment lookup (O(log N) per sample)
- [ ] Per-segment Signalsmith Stretch instanca
- [ ] Latency compensation za stretcher

### Faza 4: Flutter UI
- [ ] WarpMarker vizuelizacija u clip_widget.dart
- [ ] Drag-to-warp interaction (pomeri marker → stretch audio)
- [ ] Transient display (sive tačke iznad waveform-a)
- [ ] Quantize-to-grid button + strength parameter
- [ ] Warp on/off toggle per clip

### Faza 5: Quantize + Cross-track
- [ ] Snap markere na grid (1/4, 1/8, 1/16, triplet)
- [ ] Strength parameter (0-100%)
- [ ] Cross-track linked markers (Reaper-style)
- [ ] Undo/redo podrška

### Ostalo
- [ ] SlotLab CUSTOM Events Tab

---

## SVE ZAVRŠENO (2026-03-21)

- **Signalsmith Stretch** (RT-5) — zamena za Phase Vocoder, MIT licenca, ~Élastique kvalitet
- **Dep Upgrade Faza 3+4** — cpal 0.17, wgpu 28, wide 1.2, glam 0.32, candle 0.9, freezed 3.0, objc2 0.6, Edition 2024, wee_alloc removed
- **Flutter UI** — Rate/Pitch sliders, SRC dropdown, Adaptive diagnostics, state persistence
- **Engine** — Sinc 384-tap SIMD, r8brain offline SRC, adaptive quality, AudioStretcher, warp/elastic panels
- **5 QA rundi** — 25+ bagova, 424 testova, 0 errors

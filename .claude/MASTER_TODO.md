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

## SLEDEĆA SESIJA — Prioritet

### 1. Dep Upgrade Faza 4

- [ ] `objc` 0.2 → `objc2` 0.5+ (rf-plugin, rf-plugin-host)
- [ ] Edition 2021 → 2024 (7 crate-ova)
- [ ] Ukloni `wee_alloc` iz rf-wasm

### 2. SlotLab CUSTOM Events Tab

- [ ] Custom Events sistem u CUSTOM tabu (levi panel)
- [ ] ID format: `custom_<name>`

### 3. Ukloni debug dijagnostiku iz panela (opciono)

- [ ] `_diagStatus` / `_updateDiag` iz audio_warping_panel.dart i elastic_audio_panel.dart
- [ ] `debug_track_clip_state` FFI (korisno za dev, može ostati behind flag)

---

## ZAVRŠENO (2026-03-21)

### Signalsmith Stretch integracija (RT-5)
- `audio_stretcher.rs` — Signalsmith wrapper (MIT, kvalitet ~Élastique Pro)
- Zamena za Phase Vocoder (obrisan `phase_vocoder.rs`)
- `process_clip_with_crossfade_pv` koristi Signalsmith za pitch/time
- Elastic tab: pitch shift bez promene brzine ✓
- Warp tab: time stretch sa pitch kompenzacijom
- Bypass čuva parametre, ne resetuje
- State persistence pri tab switchovanju (static Map per track)
- 3 QA runde, 21+ bugova pronađeno i fiksirano
- `signalsmith-stretch` crate, `AudioStretcher` sa AtomicBool reset, bounds check

### Dep Upgrade Faza 3
- cpal 0.15→0.17, wgpu 24→28, wide 0.7→1.2, glam 0.29→0.32
- candle-core/nn 0.8→0.9, freezed 2.5→3.0

### Flutter UI
- Per-clip Rate/Pitch sliders + Preserve Pitch toggle (clip inspector)
- SRC quality dropdown (7 nivoa) u Project Settings
- Adaptive quality diagnostics panel sa auto-refresh

### Engine (RT-1 through RT-4)
- Blackman-Harris Sinc 384-tap + SIMD (NEON/AVX2)
- rf-r8brain offline SRC, adaptive per-voice quality
- preserve_pitch toggle, Signalsmith Stretch wiring u process_clip_with_crossfade
- elastic_pro_set_ratio/pitch rade direktno na klipovima (bez ElasticPro instance)

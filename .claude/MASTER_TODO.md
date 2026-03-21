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

### 1. SlotLab CUSTOM Events Tab

- [ ] Custom Events sistem u CUSTOM tabu (levi panel)
- [ ] ID format: `custom_<name>`
- [ ] Korisnik kreira evente van predefinisanih stage-ova
- [ ] Detaljan plan u MEMORY

### 2. Ukloni debug dijagnostiku iz panela

- [ ] `_diagStatus` / `_updateDiag` iz audio_warping_panel.dart i elastic_audio_panel.dart
- [ ] `debug_track_clip_state` FFI — može ostati ali sakriti iz UI-a

### 3. rf-coverage + rf-fuzz: `gen` keyword fix za Edition 2024

- [ ] Preimenuj `gen` identifikator u oba crate-a
- [ ] Upgrade na edition 2024

---

## SVE ZAVRŠENO (2026-03-21)

### Dep Upgrade Faza 4 (commit 052baa4f)
- objc 0.2 → objc2 0.6 (rf-plugin + rf-plugin-host)
- 37 msg_send migriranih, 3 ClassDecl → ClassBuilder, cocoa/objc uklonjeni
- objc2-foundation 0.3, objc2-app-kit 0.3, block2 0.6
- Edition 2021 → 2024 (6 crate-ova: rf-audio-diff, rf-bench, rf-connector, rf-ingest, rf-release, rf-stage)
- wee_alloc uklonjen iz rf-wasm
- 4 QA runde, svi bagovi fiksirani

### Signalsmith Stretch (RT-5, commit b5bd6510)
- audio_stretcher.rs — Signalsmith wrapper (MIT, kvalitet ~Élastique Pro)
- Zamena za Phase Vocoder (obrisan phase_vocoder.rs)
- Elastic tab: pitch shift bez promene brzine
- Warp tab: time stretch sa pitch kompenzacijom
- Bypass čuva parametre, state persistence pri tab switch

### Dep Upgrade Faza 3
- cpal 0.15→0.17, wgpu 24→28, wide 0.7→1.2, glam 0.29→0.32
- candle-core/nn 0.8→0.9, freezed 2.5→3.0

### Flutter UI
- Per-clip Rate/Pitch sliders + Preserve Pitch toggle
- SRC quality dropdown (7 nivoa) u Project Settings
- Adaptive quality diagnostics panel sa auto-refresh

### Engine (RT-1 through RT-5)
- Blackman-Harris Sinc 384-tap + SIMD, rf-r8brain offline SRC
- Adaptive per-voice quality, preserve_pitch toggle
- Signalsmith Stretch wiring u process_clip_with_crossfade
- elastic_pro_set_ratio/pitch direktno na klipovima
- 4 QA runde, 25+ bugova, 424 testova

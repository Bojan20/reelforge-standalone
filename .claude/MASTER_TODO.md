# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-21

## Key File Map

| System | Entry Point | Big Files |
|--------|------------|-----------|
| DAW UI | `main_layout.dart` | `timeline_screen.dart` |
| SlotLab | `slot_lab_screen.dart` (13K+) | `slot_lab_coordinator.dart` |
| Engine | `playback.rs` (7600+) | `sinc_table.rs`, `phase_vocoder.rs` |
| r8brain | `crates/rf-r8brain/` (6 modula, 1713 linija) | offline render SRC |
| FFI | `native_ffi.dart` (21K+) | `crates/rf-bridge/src/lib.rs` |

## Active Traps

- `slot_lab_screen.dart` — 13K+ lines, NE MOŽE se razbiti
- `native_ffi.dart` — 21K+, auto-generated, READ ONLY
- `desktop_drop` 0.5 — MainFlutterWindow.swift hack, NE DIRATI
- Audio thread: NULA alokacija u `fill_buffer()` / `process_one_shot_voices()`

---

## SLEDEĆA SESIJA — Prioritet

### 1. Full Build + Runtime Test

- [ ] `cargo build --release` + copy dylibs + xcodebuild (full build procedura)
- [ ] Runtime test: preserve_pitch na klipu sa stretch_ratio != 1.0
- [ ] Runtime test: SRC quality dropdown — promena kvaliteta tokom playback-a
- [ ] Runtime test: adaptive quality monitor — CPU load prikaz
- [ ] Runtime test: per-clip Rate/Pitch sliders u clip inspector

### 2. PV Latency Compensation

- [ ] PV latency = fft_size (2048) samples — kompenzovati u transport/timeline
- [ ] `process_clip_with_crossfade` (offline/bounce path) nema PV — dodati ili rutirati kroz `process_clip_simple`

### 3. Dep Upgrade Faza 4

- [ ] `objc` 0.2 → `objc2` 0.5+ (rf-plugin, rf-plugin-host)
- [ ] Edition 2021 → 2024 (7 crate-ova)
- [ ] Ukloni `wee_alloc` iz rf-wasm

### 4. Planned: SlotLab CUSTOM Events Tab

- [ ] Custom Events sistem u CUSTOM tabu (levi panel)
- [ ] ID format: `custom_<name>`
- [ ] Detaljan plan u MEMORY

---

## ZAVRŠENO (2026-03-21, sesija 2 — commit eb39271c)

- RT-4b: Phase vocoder wiring u `process_clip_simple()`
  - Stereo L/R: odvojeni vocoder par `(PhaseVocoder, PhaseVocoder)` po klipu
  - Thread-local PV scratch buffers (5 buffera, zero audio-thread alloc)
  - `get_mut` + bypass fallback (NIKAD `or_insert_with` na audio thread-u)
  - Seek reset, COLA normalizacija (Hann^2 gain correction)
  - FFI: `clip_set_preserve_pitch`, `clip_update_vocoder_pitch`, `clip_set_pitch_shift`, `clip_set_stretch_ratio`
- RT-4c: Formant preservation — cepstral envelope (guarded, zero CPU kad off)
  - `cepstral_envelope_inplace()` sa `exp()` clamp(-50, 50)
- Dep Upgrade Faza 3:
  - `cpal` 0.15→0.17, `wgpu` 24→28, `wide` 0.7→1.2, `glam` 0.29→0.32
  - `candle-core/nn` 0.8→0.9, `freezed` 2.5→3.0
- Flutter UI:
  - Per-clip Rate/Pitch sliders + Preserve Pitch toggle (clip inspector)
  - SRC quality dropdown (7 nivoa) u Project Settings
  - Adaptive quality diagnostics panel sa auto-refresh (500ms timer)
  - `pitchShift` + `preservePitch` u TimelineClip model
- QA audit: 9 bugova pronađeno i fiksirano
  - Stereo PV (critical), audio-thread alloc (critical), null pointer (critical)
  - Pitch slider FFI mismatch (critical), COLA gain (serious)
  - exp overflow, monitor refresh, sample rate, rate reset

## ZAVRŠENO (2026-03-21, sesija 1)

- RT-1: Blackman-Harris Sinc + SIMD (NEON/AVX2) — `sinc_table.rs`
- RT-1b: rf-r8brain crate (6 modula, 1713 linija) — offline render SRC
- RT-2: Adaptive per-voice quality — CPU budget tracker
- RT-3: preserve_pitch toggle + NaN guards — `track_manager.rs`
- RT-4: Phase vocoder core — `phase_vocoder.rs` (STFT, transient detection, OLA)
- ASSIGN tab: dvored slots, 6-bojni sistem, undo/redo, GAME_START fix
- Deps: serde_yml, rand 0.9, workspace consolidation
- QA: 40+ bugova pronađeno i fiksirano kroz 8 QA rundi

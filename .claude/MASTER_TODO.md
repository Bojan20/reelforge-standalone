# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-21

## Key File Map

| System | Entry Point | Big Files |
|--------|------------|-----------|
| DAW UI | `main_layout.dart` | `timeline_screen.dart` |
| SlotLab | `slot_lab_screen.dart` (13K+) | `slot_lab_coordinator.dart` |
| Engine | `playback.rs` (7200+) | `sinc_table.rs`, `phase_vocoder.rs` |
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

### 2. Per-channel Phase Vocoders

- [ ] Stereo PV: odvojeni L/R vocoder instance (trenutno L i R idu kroz isti PV)
- [ ] Latency compensation: PV latency = fft_size samples, kompenzovati u transport

### 3. Full Build + Runtime Test

- [ ] `cargo build --release` + copy dylibs + xcodebuild
- [ ] Runtime test: preserve_pitch na klipu sa stretch_ratio != 1.0
- [ ] Runtime test: SRC quality dropdown — promena kvaliteta tokom playback-a
- [ ] Runtime test: adaptive quality monitor — CPU load prikaz

---

## ZAVRŠENO OVE SESIJE (2026-03-21, sesija 2)

- RT-4b: Phase vocoder wiring u `process_clip_simple()` — preserve_pitch path
  - Thread-local PV scratch buffers (PV_SCRATCH_L/R, PV_OUT_L/R, PV_GAIN_SCRATCH)
  - try_write lock sa bypass fallback (nikad blokira audio thread)
  - Seek reset za sve vocodere
  - FFI: `clip_set_preserve_pitch()`, `clip_update_vocoder_pitch()`
- RT-4c: Formant preservation — cepstral envelope extraction + reapply
  - `cepstral_envelope_inplace()`: log-mag → IFFT → lifter → FFT → exp
  - Correction: `mag_shifted * (orig_envelope / shifted_envelope)`, clamped ±20dB
  - 7 phase_vocoder testova, svi prolaze
- Dep Upgrade Faza 3:
  - `cpal` 0.15 → 0.17 (SampleRate tuple struct → u32 alias)
  - `wgpu` 24.0 → 28.0 (Maintain→PollType, DeviceDescriptor, PipelineLayout, RenderPass)
  - `wide` 0.7 → 1.2 (clean upgrade)
  - `glam` 0.29 → 0.32 (clean upgrade)
  - `candle-core/nn` 0.8 → 0.9 (clean upgrade)
  - `freezed` 2.5.8 → 3.0+ / `freezed_annotation` 2.4.4 → 3.0+
- Flutter UI:
  - Per-item Rate/Pitch sliders u clip inspector (+ Preserve Pitch toggle)
  - `pitchShift` i `preservePitch` polja u TimelineClip model
  - SRC quality dropdown u Project Settings (Point→Linear→Sinc16/64/192/384→r8brain)
  - Adaptive quality diagnostics panel (active voices, degraded count, CPU load bar)
  - FFI: `set_src_quality()`, `get_src_quality()`, `get_adaptive_quality_stats()`
- Bugfix: `preview.rs:644` — `RtState::new` missing sample_rate arg
- QA: cargo build 0 errors, flutter analyze 0 issues, 425 tests passing

## ZAVRŠENO RANIJE (2026-03-21, sesija 1)

- RT-1: Blackman-Harris Sinc + SIMD (NEON/AVX2) — `sinc_table.rs`
- RT-1b: rf-r8brain crate (6 modula, 1713 linija) — offline render SRC
- RT-2: Adaptive per-voice quality — CPU budget tracker u `process_one_shot_voices()`
- RT-3: preserve_pitch toggle + NaN guards — `track_manager.rs`
- RT-4: Phase vocoder core — `phase_vocoder.rs` (STFT, transient detection, OLA)
- ASSIGN tab: dvored slots, 6-bojni sistem, undo/redo, GAME_START fix
- Deps: serde_yml, rand 0.9, workspace consolidation
- QA: 40+ bugova pronađeno i fiksirano kroz 8 QA rundi

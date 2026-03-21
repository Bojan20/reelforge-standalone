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

### 1. Phase Vocoder → rustfft + playback integracija

- [ ] Zameni `dft_real`/`idft_real` O(N²) sa `rustfft` O(N log N) u `phase_vocoder.rs`
  - Dodaj `rustfft` dependency u rf-engine Cargo.toml (već u workspace)
  - Pre-alociraj `FftPlanner` + plans u `PhaseVocoder::new()`
  - `process_frame()`: koristiti `fft.process()` umesto naive DFT
- [ ] Integracija u `render_clip_to_buffer()` u `playback.rs`
  - Kad `clip.preserve_pitch == true && clip.stretch_ratio != 1.0`:
  - Posle sinc SRC: primeni `PhaseVocoder` sa `pitch_factor = 1.0 / stretch_ratio`
  - Per-clip `PhaseVocoder` instance (pre-alocirano pri clip load, NE na audio thread)
- [ ] Formant preservation: spectral envelope extraction + reapply

### 2. Dep Upgrade Faza 3

| Crate | Trenutno | Cilj | Napomena |
|-------|----------|------|----------|
| `cpal` | 0.15 | 0.17.3 | Audio I/O — TESTIRATI LATENCY |
| `wgpu` | 24.0 | 28.0.0 | GPU viz — 4 major-a |
| `wide` | 0.7 | 1.1.1 | SIMD major |
| `glam` | 0.29 | 0.32.1 | Matematika |
| `candle-core/nn` | 0.8 | 0.9.2 | ML inference |
| `freezed` (Flutter) | 2.5.8 | 3.2.5 | Code gen major |

### 3. Dep Upgrade Faza 4

- [ ] `objc` 0.2 → `objc2` 0.5+ (rf-plugin, rf-plugin-host)
- [ ] Edition 2021 → 2024 (7 crate-ova)
- [ ] Ukloni `wee_alloc` iz rf-wasm

### 4. Flutter UI

- [ ] Per-item rate/pitch sliders u timeline-u
- [ ] SRC quality settings dropdown (Point/Linear/Sinc16/64/192/384)
- [ ] Adaptive quality diagnostics u UI

---

## ZAVRŠENO OVE SESIJE (2026-03-21)

- RT-1: Blackman-Harris Sinc + SIMD (NEON/AVX2) — `sinc_table.rs`
- RT-1b: rf-r8brain crate (6 modula, 1713 linija) — offline render SRC
- RT-2: Adaptive per-voice quality — CPU budget tracker u `process_one_shot_voices()`
- RT-3: preserve_pitch toggle + NaN guards — `track_manager.rs`
- RT-4: Phase vocoder core — `phase_vocoder.rs` (STFT, transient detection, OLA)
- ASSIGN tab: dvored slots, 6-bojni sistem, undo/redo, GAME_START fix
- Deps: serde_yml, rand 0.9, workspace consolidation
- QA: 40+ bugova pronađeno i fiksirano kroz 8 QA rundi

# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-21

## Key File Map

| System | Entry Point | Big Files |
|--------|------------|-----------|
| DAW UI | `main_layout.dart` | `timeline_screen.dart` |
| SlotLab | `slot_lab_screen.dart` (13K+) | `slot_lab_coordinator.dart` |
| SlotLab providers | `slot_engine_provider.dart`, `slot_stage_provider.dart`, `slot_audio_provider.dart` | |
| Mixer | `engine_connected_layout.dart` | `mixer_provider.dart` |
| FFI | `native_ffi.dart` (21K+) | `crates/rf-bridge/src/lib.rs` |
| Offline DSP | `offline_processing_provider.dart` | `crates/rf-offline/src/pipeline.rs` |
| DI | `service_locator.dart` | `main.dart` (provider tree) |

## Active Traps

- `slot_lab_screen.dart` — 13K+ lines, NE MOŽE se razbiti (Dart State class limitation)
- `native_ffi.dart` — 21K+ lines, auto-generated, READ ONLY
- `slot_lab_provider.dart` je MRTAV KOD — koristi se `SlotLabCoordinator` (typedef)
- `desktop_drop` 0.5 — MainFlutterWindow.swift hack zavisi od plugin ponašanja, NE DIRATI

## Real-Time Resampling Engine (BEYOND Reaper)

**Cilj:** Bolji od Reapera — r8brain-level kvalitet, AVX-512 SIMD, adaptive per-voice quality, custom phase vocoder sa formant preservation.
**Referenca:** `REAPER_SRC_ANALYSIS.md` (WDL arhitektura, quality modovi, processing lanac)

### Faza RT-1: Core Resampler (`rf-engine/src/resampler.rs`)

- [ ] **`Resampler` struct** — Blackman-Harris 4-term windowed sinc
  - Pre-computed sinc tabela (sinc_size × sinc_interp_size)
  - Ring buffer za input, phase accumulator za fractional tracking
  - Zero allocation u audio path-u — sve pre-alocirano pri init/mode change
- [ ] **`ResampleMode` enum** — Point, Linear, IirLinear(N), Sinc(16/64/192/384/512/768), R8brain
  - Default playback: Sinc(64), Default render: R8brain
- [ ] **r8brain port u Rust** — MIT licenca, header-only C++ → čist Rust port
  - 2x oversample → banka kratkih polynomial sinc delay filtera
  - Minimum-phase kernel via Hilbert transform u cepstrum domenu (manje pre-ringing od linear sinc)
  - Bolji kvalitet od WDL 768pt sinc uz MANJE CPU — ovo je naš HIGHEST mode
- [ ] **`FeedMode`** — InputDriven (real-time callback) / OutputDriven (offline render)
- [ ] **AVX-512 SIMD inner loops** — `sinc_sample_mono/stereo/nch`
  - AVX-512: 8× f64 parallel (4× brže od Reaper WDL koji koristi SSE2)
  - Auto-dispatch: AVX512 → AVX2 → SSE4.2 → scalar (existing rf-dsp pattern)
- [ ] **Latency reporting** — `latency() → sinc_size / 2` samples
- [ ] **rubato ostaje za offline pipeline** (rf-offline) — custom resampler je za real-time engine

### Faza RT-2: Engine Integration + Adaptive Quality

- [ ] **`ResamplerPool`** — pre-alocira N resamplera (N = max voices) pri engine init
  - Lock-free acquire/release (atomics)
  - Svaki podržava ratio promenu bez realokacije
- [ ] **Per-voice SRC** — `PlaybackVoice` dobija Resampler iz pool-a kad `file_sr != project_sr`
  - Bypass kad SR matchuje (nula overhead, nula latency)
- [ ] **`process_block()` integration** — čitaj originalni SR → resampler → project SR buffer
- [ ] **Project sample rate** — `project_sample_rate: u32` u `EngineConfig`
  - Default: 48000, UI dropdown (44100/48000/88200/96000)
- [ ] **Dual quality settings** — playback mode (tipično Sinc64) + render mode (tipično R8brain)
- [ ] **Adaptive per-voice quality** (NEMA u Reaperu)
  - CPU overload → automatska degradacija PER-VOICE (ne globalno)
  - Solo/selected glasovi zadržavaju highest quality
  - Pozadinski glasovi: Sinc384 → Sinc64 → Linear po CPU budžetu
  - Vrača se na viši kvalitet čim CPU dozvoli

### Faza RT-3: Per-Item Properties

- [ ] **Playback rate** — `PlaybackVoice.playback_rate: f64` (1.0 = normalno)
  - Bez preserve pitch = varispeed (menja ratio u realnom vremenu)
  - Sa preserve pitch = time-stretch + SRC
- [ ] **Pitch shift** — `PlaybackVoice.pitch_semitones: f64`
  - Implementacija: rate change × inverse time-stretch
- [ ] **Preserve pitch toggle** — per-item boolean
- [ ] **Scrub/Shuttle** — variable speed -4x..+4x, automatski Linear mode za CPU saving
- [ ] **Master playback rate** — globalni varispeed slider sa automatable envelope

### Faza RT-4: Time-Stretch + DAW Features

- [ ] **Custom phase vocoder** (BOLJI od Reaper Simple Windowed)
  - Transient-preserving OLA (Driedger/Müller 2014 algoritam)
  - Spectral peak locking — čistiji harmonici od standard OLA
  - **Formant preservation** za vokale (Reaper ovo NEMA bez Elastique Soloist licence)
- [ ] **SoundTouch integracija** (WSOLA, LGPL) — fast fallback mode
- [ ] **Per-item stretch algorithm** — Phase Vocoder / SoundTouch / Simple Windowed
- [ ] **Auto-SR match na import** — user pref: "Convert on import" vs "Real-time SRC"
- [ ] **Latency compensation (PDC)** — SRC latency (sinc_size/2) u playback scheduling
- [ ] **Xrun handling** — tihi output tokom dropout-a, adaptive quality per-voice
- [ ] **SRC CPU metrics** — u diagnostics panel

### Prednosti nad Reaperom

1. **r8brain Rust port** — highest quality mode (bolji od WDL 768pt sinc, efikasniji CPU)
2. **AVX-512 SIMD** — 8× f64 parallel sinc, 4× brži od WDL SSE2
3. **Adaptive per-voice quality** — CPU overload degradira pozadinske glasove, solo/selected ostaju na max
4. **Formant-preserving phase vocoder** — Reaper zahteva Elastique Soloist licencu za ovo
5. **Zero-copy Rust** — nema C++ overhead, ring buffer direktan pristup

### Pravila

- Audio thread: NULA alokacija u `process_block()` — ring buffer + sinc tabela pre-alocirani
- Processing lanac per-item: Source(orig SR) → SRC → Rate/Stretch → Pitch → Output(project SR)
- SIMD: AVX512 → AVX2 → SSE4.2 → scalar auto-dispatch za sinc inner loops
- Testiranje: bit-exact comparison sa WDL output + ABX test vs r8brain C++ referenca

---

## Dependency Upgrade — Preostalo

### Faza 3 — Teški ali vredni

| Crate/Paket | Trenutno | Cilj | Napomena |
|-------------|----------|------|----------|
| `cpal` | 0.15 | 0.17.3 | Audio I/O core — TESTIRATI LATENCY |
| `wgpu` | 24.0 | 28.0.0 | GPU viz — 4 major-a |
| `wide` | 0.7 | 1.1.1 | SIMD major |
| `glam` | 0.29 | 0.32.1 | Matematika |
| `candle-core/nn` | 0.8 | 0.9.2 | ML inference |
| `tract-onnx/core` | 0.21 | 0.23 | ML inference |
| `freezed` (Flutter) | 2.5.8 | 3.2.5 | Code gen major |

### Faza 4 — Čišćenje

- [ ] `objc` 0.2 → `objc2` 0.5+ (rf-plugin, rf-plugin-host)
- [ ] `cocoa` 0.26 → `objc2-app-kit`
- [ ] `block` 0.1 → `block2`
- [ ] Edition 2021 → 2024 (rf-ml, rf-spatial, rf-master, rf-pitch, rf-restore, rf-realtime, rf-plugin-host)
- [ ] Ukloni `wee_alloc` iz rf-wasm

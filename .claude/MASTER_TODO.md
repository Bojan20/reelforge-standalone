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
**Referenca:** `REAPER_SRC_ANALYSIS.md`

### Postojeća infrastruktura (VEĆ RADI)

- `OneShotVoice.fill_buffer()` (`playback.rs:1194`) — real-time playback sa SRC + pitch
- `lanczos3_sample()` (`playback.rs:973`) — 6-tap Lanczos-3 interpolacija (~-90dB noise floor)
- `SampleRateConverter` (`audio_import.rs:622`) — offline Lanczos-3 za batch import
- `rate_ratio = audio.sample_rate / engine_sample_rate` — automatski SRC per-voice
- `pitch_semitones` → `pitch_ratio = 2^(semi/12)` — već radi varispeed pitch
- `engine_sample_rate` keširan u svakom OneShotVoice pri aktivaciji
- 32 OneShotVoice pool-a, zero-alloc `fill_buffer()`

### Faza RT-1: Zamena Lanczos-3 → Blackman-Harris Sinc + Quality Modes

Zamena `lanczos3_sample()` sa konfigurablinim sinc kernel-om. NE novi crate — zamena JEDNE FUNKCIJE + ring buffer.

- [ ] **`sinc_table.rs`** — pre-computed Blackman-Harris 4-term windowed sinc tabela
  - Generiše se pri init/mode change, NE na audio thread-u
  - `sinc_size` × `sinc_interp_size` (npr. 64×32 = 2048 f64 koeficijenata)
  - Jedan `Vec<f64>` — alociran JEDNOM, nikad na audio thread-u
- [ ] **`ResampleMode` enum** u `playback.rs`
  - `Point` — nearest-neighbor (za lo-fi efekat)
  - `Linear` — lerp (za scrub, najniži CPU)
  - `Sinc(16)` — brz sa OK kvalitetom
  - `Sinc(64)` — **default playback** (= Reaper Medium)
  - `Sinc(192)` — good render
  - `Sinc(384)` — **default render** (= Reaper Better)
  - `Sinc(512/768)` — extreme quality
  - `R8brain` — highest (Faza RT-1b, zasebna implementacija)
- [ ] **`sinc_sample()` zamena** u `fill_buffer()` — umesto `lanczos3_sample()`
  - Koristi pre-computed tabelu sa sub-sample interpolacijom
  - Ring buffer za input history (sinc_size frames unatrag)
  - Per-voice ring buffer pre-alociran u OneShotVoice (max sinc_size = 768 × channels × f32)
- [ ] **SIMD inner loop** — `sinc_convolve_mono/stereo`
  - AVX-512: 8× f64 parallel (4× brže od WDL SSE2)
  - AVX2: 4× f64, SSE4.2: 2× f64, scalar fallback
  - Auto-dispatch po existing rf-dsp pattern
- [ ] **Dual quality settings** — `playback_resample_mode` + `render_resample_mode` u EngineConfig
- [ ] **Latency** — `sinc_size / 2` samples, reportovano za PDC

### Faza RT-1b: r8brain Rust Port

- [ ] **Port `r8brain-free-src`** (MIT, header-only C++) u čist Rust
  - 2x oversample → banka kratkih polynomial sinc delay filtera
  - Minimum-phase kernel via Hilbert transform (manje pre-ringing od linear sinc)
  - Bolji kvalitet od Sinc(768) uz manje CPU
  - Ovo je naš HIGHEST mode — iznad čega Reaper nema ništa

### Faza RT-2: Adaptive Per-Voice Quality (NEMA u Reaperu)

- [ ] **CPU budget tracker** — meri vreme svake voice u `fill_buffer()`
  - Atomic counter per-block, reset svakih N blokova
- [ ] **Automatska degradacija** — kad block time > threshold:
  - Solo/selected glasovi: UVEK highest quality
  - Pozadinski glasovi: Sinc384 → Sinc64 → Linear po budžetu
  - Vraća se na viši kvalitet čim CPU dozvoli
- [ ] **Per-voice `ResampleMode`** — umesto globalnog, svaki voice ima svoj mode
  - Default = projekat playback mode
  - Override za solo/selected = highest
  - Degraded = automatski smanjen

### Faza RT-3: Per-Item Properties

VEĆ DELOMIČNO RADI: `pitch_semitones` i `rate_ratio` postoje u `OneShotVoice`.

- [ ] **Preserve pitch toggle** — per-voice boolean
  - OFF (trenutno): varispeed = rate × pitch → oba menjaju speed
  - ON (novo): rate menja speed bez pitch promene (zahteva time-stretch)
- [ ] **Playback rate UI** — slider per-item u timeline-u
- [ ] **Scrub/Shuttle** — variable speed -4x..+4x, automatski Linear mode
- [ ] **Master playback rate** — globalni varispeed slider + automatable envelope

### Faza RT-4: Time-Stretch + DAW Features

- [ ] **Custom phase vocoder** (BOLJI od Reaper Simple Windowed)
  - Transient-preserving OLA (Driedger/Müller 2014)
  - Spectral peak locking — čistiji harmonici
  - **Formant preservation** za vokale (Reaper NEMA bez Elastique licence)
- [ ] **SoundTouch** (WSOLA, LGPL) — fast fallback
- [ ] **Per-item stretch algorithm selection**
- [ ] **Auto-SR match na import** — "Convert on import" vs "Real-time SRC"
- [ ] **PDC** — SRC latency (sinc_size/2) u playback scheduling
- [ ] **Xrun handling** — tihi output + adaptive quality per-voice
- [ ] **SRC CPU metrics** u diagnostics panel

### Prednosti nad Reaperom

1. **r8brain Rust port** — bolji od WDL 768pt sinc, efikasniji CPU
2. **AVX-512 SIMD** — 8× f64 parallel, 4× brži sinc od WDL SSE2
3. **Adaptive per-voice quality** — degradira pozadinske, solo/selected na max
4. **Formant-preserving phase vocoder** — Reaper zahteva Elastique licencu
5. **Zero-copy Rust** — ring buffer direktan pristup, nema C++ overhead

### Pravila

- Audio thread: NULA alokacija u `fill_buffer()` — ring buffer + sinc tabela pre-alocirani
- Processing lanac: Source(orig SR) → SRC(sinc) → Rate/Stretch → Pitch → Output(project SR)
- SIMD: AVX512 → AVX2 → SSE4.2 → scalar auto-dispatch
- Testiranje: ABX test sinc output vs WDL referenca + r8brain C++ referenca

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

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

### Arhitekturna odluka: Real-Time vs Offline SRC

- **Real-time playback:** Sinc(64) sa Blackman-Harris + SIMD (zero-alloc, zero-lock)
- **Offline render:** rf-r8brain crate (multi-stage, heap allocs, highest quality)
- R8brain NIJE za audio thread — heap alokacije, FFT plans, Vec::resize()
- Sinc(64/384) + SIMD daje Reaper-level kvalitet za playback (isti kernel)
- R8brain za final bounce daje IZNAD Reapera (206dB attenuation)

### Faza RT-1: Blackman-Harris Sinc + SIMD — ✅ ZAVRŠENO

- [x] `sinc_table.rs` — BH4 windowed sinc, pre-computed tabela, ResampleMode enum
- [x] Zamena svih `lanczos3_sample()` (7 poziva) sa `sinc_table::interpolate_sample()`
- [x] SIMD: NEON (aarch64) + AVX2 (x86_64) dot product za sinc convolution
- [x] Gather strided → contiguous stack buffer → SIMD dot product
- [x] Dinamička tabela (RwLock) — regeneracija pri mode change
- [x] Dual quality: `set_playback_resample_mode()` — Point/Linear/Sinc(16-768)
- [x] QA: window formula fix, NaN/Inf guard, channels=0 guard, min sinc_size=4

### Faza RT-1b: r8brain Rust Port (`crates/rf-r8brain/`)

Novi crate — pure Rust port r8brain-free-src (MIT licenca). Multi-stage resampling pipeline.
Atribucija: "Sample rate converter designed by Aleksey Vaneev of Voxengo"

**Modul 1: Kaiser window + sinc filter generator**
- [ ] Kaiser window sa Bessel I0 aproksimacijom (dva polinomijalna opsega)
- [ ] Power-raised window varijanta
- [ ] Sinc filter generacija sa konfigurabilinim transition band + stopband attenuation
- [ ] Filter length iz attenuation-a (empirijske formule)

**Modul 2: Polynomial fractional interpolator (CORE inovacija)**
- [ ] Filter bank generacija na diskretnim frakcionim pozicijama
- [ ] FilterFracs = ceil(6.4^(ReqAtten/50)) — npr. ~2700 pozicija za 180dB
- [ ] 8-tačka kubni spline koeficijenti (`calcSpline3p8Coeffs`)
- [ ] Inner loop: `output += (a0 + a1*x + a2*x² + a3*x³) * input[i]`
- [ ] Podržava red 0 (nearest), 1 (linear), 2 (quadratic), 3 (cubic)

**Modul 3: Half-band up/down sampler**
- [ ] Sparse simetrični FIR (4-14 tapova) za 2x up/downsample
- [ ] Kaskadno za veće faktore (4x = 2x→2x)
- [ ] Pre-computed koeficijenti iz .inc fajlova

**Modul 4: FFT-based overlap-save block convolver**
- [ ] Overlap-save konvolucija za anti-aliasing/anti-imaging
- [ ] Koristi `rustfft` (već u workspace dependencies)
- [ ] O(N log N) umesto O(N²) za duge filtere

**Modul 5: Minimum-phase transform**
- [ ] Forward FFT → log-magnitude → inverse FFT → cepstrum
- [ ] Hilbert transform na cepstrum
- [ ] Forward FFT → restore magnitude → inverse FFT → minimum-phase kernel
- [ ] Group delay kompenzacija

**Modul 6: Pipeline orchestrator (CDSPResampler)**
- [ ] Automatska konstrukcija pipeline-a na osnovu source/dest SR ratio
- [ ] Presets: 206dB (27-bit), 180dB (24-bit), 136dB (16-bit)
- [ ] `process()` — push input → get output (input-driven za real-time)
- [ ] Integracija sa `sinc_table.rs` ResampleMode::R8brain

**Testiranje:**
- [ ] Bit-exact comparison sa r8brain C++ referenca (svaki modul)
- [ ] ABX listening test: r8brain Rust vs r8brain C++ vs Sinc(768)
- [ ] Latency verification
- [ ] Zero-allocation u audio path-u (svi bufferi pre-alocirani)

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

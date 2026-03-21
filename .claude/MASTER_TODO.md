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

### Faza RT-2: Adaptive Per-Voice Quality (NEMA u Reaperu) — ✅ ZAVRŠENO

- [x] Per-voice `voice_resample_mode` u OneShotVoice (umesto globalnog)
- [x] CPU budget tracker: `Instant::now()` per-voice, kumulativno per-block
- [x] Budget = 50% block time (npr. 2.65ms za 256 samples @ 48kHz)
- [x] Automatska degradacija: kad cumulative > budget, background voices → Linear
- [x] DAW/Browser voices UVEK na globalnom kvalitetu (nikad degradirani)
- [x] Vraća se na viši kvalitet čim CPU dozvoli (reset svaki block)

### Faza RT-3: Per-Item Properties — ✅ ENGINE KOMPLETNO

Sve VEĆ IMPLEMENTIRANO u engine-u (prethodni rad):
- [x] `stretch_ratio` — per-clip playback rate (Clip struct)
- [x] `pitch_shift` — per-clip pitch in semitones
- [x] `reversed` — reverse playback
- [x] `varispeed_rate` + `varispeed_enabled` — master playback rate (PlaybackEngine)
- [x] `scrub_velocity` — scrub/shuttle (PlaybackPosition)
- [x] `ClipEnvelope` — per-sample rate/pitch automation
- [x] `preserve_pitch` — per-clip toggle (NOVO: varispeed vs time-stretch)

Fali SAMO:
- [ ] **Flutter UI** za per-item rate/pitch sliders u timeline-u
- [ ] **Time-stretch** kad preserve_pitch=true (RT-4)

### Faza RT-4: Time-Stretch + DAW Features

- [x] **Phase vocoder** (`rf-engine/src/phase_vocoder.rs`)
  - STFT → phase advance correction → ISTFT (overlap-add)
  - Transient detection: energy ratio reset phase at onsets
  - Hann window, configurable FFT size (1024/2048) and overlap (4×/8×)
  - Pre-allocated buffers — zero-alloc process() (osim DFT koji treba rustfft)
  - set_pitch_factor(), set_formant_preserve(), reset()
- [ ] **Integracija u playback pipeline** — kad preserve_pitch=true, primeni PV posle sinc
- [ ] **Zameni DFT sa rustfft** — O(N²) → O(N log N) za real-time
- [ ] **Formant preservation** — spectral envelope extraction + reapply
- [ ] **SoundTouch** fallback — WSOLA za niži CPU
- [ ] **PDC** — SRC + PV latency u scheduling
- [ ] **SRC CPU metrics** u diagnostics

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

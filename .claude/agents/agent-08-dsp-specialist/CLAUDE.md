# Agent 8: DSPSpecialist

## Role
DSP processing, filters, spectrum, metering (Rust), SIMD, ML audio, mastering, pitch, restoration.

## File Ownership (~120 files)

### Rust Crates
- `crates/rf-dsp/` (65 files) — simd, automation, delay_compensation, biquad, eq, dynamics, reverb, delay, spatial, surround, convolution, linear_phase, metering, spectral, dsd, gpu
- `crates/rf-restore/` (8 files) — professional audio repair, denoising, declicking
- `crates/rf-master/` (10 files) — AI-assisted mastering, loudness optimization
- `crates/rf-pitch/` (7 files) — polyphonic pitch engine (Melodyne DNA level)
- `crates/rf-r8brain/` (7 files) — reference-grade SRC (Blackman-Harris windowed sinc)
- `crates/rf-ml/` (26 files) — ONNX model inference, Hugging Face integration, neural audio

### Flutter Panels
- `flutter_ui/lib/widgets/lower_zone/daw/process/` (all panels)
- `flutter_ui/lib/widgets/fabfilter/` (all panels)
- `flutter_ui/lib/widgets/dsp/` (all panels)
- `flutter_ui/lib/widgets/eq/` (8 files) — API550, Neve1073, Pultec, ProEQ, morph pad, room wizard, GPU spectrum, vintage inserts
- `flutter_ui/lib/widgets/lower_zone/daw/mix/lufs_meter_widget.dart`

## Critical Rules
1. **Biquad:** TDF-II form, `z1`/`z2` state variables
2. **SIMD dispatch:** avx512f → avx2 → sse4.2 → scalar fallback chain
3. **Sample rate:** Always call `set_sample_rate()` + recalculate coefficients
4. **Denormal handling:** FTZ/DAZ CPU flags + software flush-to-zero
5. **Metering:** `try_write()` everywhere, NEVER blocking `.write()` on audio thread
6. **FFT:** Hann window, correct RMS scaling, exponential smoothing
7. **Audio thread:** Only stack allocations, pre-allocated buffers, atomics, SIMD

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 7 | CRITICAL | BPM hardcoded 120.0 in 4 DSP structs | delay.rs:521,982; dynamics.rs:602; reverb.rs:2636 |
| 23 | MEDIUM | FabFilter delay slider default hardcoded | fabfilter_delay_panel.dart:1299 |

## Relationships
- **AudioEngine (1):** DSP processors run inside the audio engine graph
- **MeteringPro (21):** Metering algorithms from rf-dsp, UI from MeteringPro
- **PluginArchitect (17):** Internal plugin effects use rf-dsp algorithms
- **SpatialAudio (20):** Spatial processing uses rf-dsp primitives

## Forbidden
- NEVER hardcode BPM — always use dynamic tempo from engine
- NEVER skip SIMD fallback chain — must work on all CPUs
- NEVER allocate in audio-thread DSP processing paths
- NEVER forget to recalculate coefficients after sample rate change

# ReelForge Superiority Roadmap

> **Cilj:** Postati ULTIMATIVNI DAW u ključnim oblastima
> **Referenca:** `.claude/analysis/dsp-competitive-analysis.md`

---

## KATEGORIJE GDE MOŽEMO DOMINIRATI

Na osnovu detaljne analize 5 konkurenata (Pyramix, REAPER, Cubase, Logic Pro, Pro Tools), identifikovane su oblasti gde ReelForge može biti **objektivno superioran**.

### Već Superiorno ✅

| Oblast | Status | Prednost nad konkurencijom |
|--------|--------|----------------------------|
| **64-bit Double Throughout** | ✅ Implementirano | Pro Tools koristi 32-bit za plugins |
| **SIMD Explicit Dispatch** | ✅ Implementirano | Niko nema runtime AVX-512/AVX2/NEON |
| **Lock-Free Audio Thread** | ✅ Implementirano | Samo MassCore ima slično (drugačiji pristup) |
| **Native Spectral Processing** | ✅ Implementirano | Jedini DAW sa native spectral gate/freeze |
| **Integrated DSP Suite** | ✅ 22 panela | Svi drugi koriste externe plugine |
| **Modern Architecture** | ✅ Rust + wgpu | Svi drugi: legacy C++ |

### Achievable Superiority 🎯

| Oblast | Prioritet | Effort | Jedinstvena prednost |
|--------|-----------|--------|---------------------|
| **Sample-Accurate Automation** | P0 | Medium | BOLJI od svih (ni jedan nema pravo) |
| **DSD/DXD Native** | P1 | Medium | Jedini Rust DAW |
| **GPU-Accelerated DSP** | P2 | High | NIKO nema |
| **Hybrid Phase EQ** | P1 | Medium | FabFilter Pro-Q nivo, native |
| **AI Processing** | P2 | Very High | Rust ML ecosystem (tract/candle) |
| **Advanced Metering** | P1 | Low | Kompletna mastering suite |

---

## PHASE 1: IMMEDIATE SUPERIORITY (1-2 meseca)

### 1.1 Sample-Accurate Automation ⭐ HIGHEST PRIORITY

**Problem kod konkurencije:**
- REAPER: "Not truly sample-accurate" (potvrđeno od developera)
- VST3: Ima "sample accurate" ali još uvek stair-stepping
- Cubase/Logic/Pro Tools: Block-level automation

**Naše rešenje:**

```rust
// crates/rf-engine/src/sample_accurate_automation.rs

/// Command sa sample offset unutar bloka
#[derive(Debug, Clone, Copy)]
pub struct ParamCommand {
    /// Sample offset unutar trenutnog bloka (0..block_size)
    pub sample_offset: u32,
    /// ID parametra (unique per processor)
    pub param_id: u32,
    /// Nova vrednost
    pub value: f64,
    /// Interpolacija do sledeće vrednosti
    pub interpolation: InterpolationType,
}

#[derive(Debug, Clone, Copy)]
pub enum InterpolationType {
    /// Instant change at sample
    Step,
    /// Linear ramp over N samples
    Linear { duration_samples: u32 },
    /// Exponential ramp (za volume)
    Exponential { duration_samples: u32 },
    /// S-curve (smooth)
    SCurve { duration_samples: u32 },
}

/// Audio thread processing sa sample-accurate params
pub fn process_block_sample_accurate(
    processor: &mut dyn DspProcessor,
    buffer: &mut [f64],
    commands: &[ParamCommand],
) {
    let block_size = buffer.len();
    let mut cmd_idx = 0;

    for sample in 0..block_size {
        // Apply all commands scheduled for this exact sample
        while cmd_idx < commands.len()
            && commands[cmd_idx].sample_offset == sample as u32
        {
            processor.set_param_immediate(
                commands[cmd_idx].param_id,
                commands[cmd_idx].value,
            );
            cmd_idx += 1;
        }

        // Process with current parameter state
        buffer[sample] = processor.process_sample(buffer[sample]);
    }
}
```

**Implementacija:**

| Task | Fajl | Effort |
|------|------|--------|
| ParamCommand struct | `rf-engine/src/automation/command.rs` | S |
| Interpolation types | `rf-engine/src/automation/interpolation.rs` | M |
| Sample-accurate queue | `rf-engine/src/automation/queue.rs` | M |
| Integration sa DSP | `rf-engine/src/automation/integration.rs` | M |
| UI automation lane | `flutter_ui/.../automation_lane.dart` | L |
| Test suite | `rf-engine/tests/sample_accurate_tests.rs` | M |

**Total effort:** ~2-3 nedelje

---

### 1.2 Advanced Metering Suite

**Šta fali:**

| Meter | Status | Konkurencija |
|-------|--------|--------------|
| K-System (K-12/K-14/K-20) | ❌ TODO | Samo via plugins |
| Phase Scope (Lissajous) | ❌ TODO | Logic ima, Cubase ima |
| Spectrogram (Waterfall) | ❌ TODO | Niko native |
| PSR (Peak-to-Short-term) | ❌ TODO | Niko |
| Crest Factor | ❌ TODO | Retko |
| Stereo Vectorscope | ❌ TODO | Pro level |

**Implementacija:**

```rust
// crates/rf-dsp/src/metering/k_system.rs

/// Bob Katz K-System metering
pub struct KSystemMeter {
    pub mode: KMode,
    pub rms_window_ms: f64,
    rms_buffer: Vec<f64>,
    sample_rate: f64,
}

#[derive(Debug, Clone, Copy)]
pub enum KMode {
    /// K-20: Classical, large dynamic range
    /// 0 dB = -20 dBFS, loudest = +4 dB on meter = -16 dBFS
    K20,
    /// K-14: Pop/Rock, moderate dynamic range
    /// 0 dB = -14 dBFS
    K14,
    /// K-12: Broadcast, limited dynamic range
    /// 0 dB = -12 dBFS
    K12,
}

impl KSystemMeter {
    pub fn reference_level_dbfs(&self) -> f64 {
        match self.mode {
            KMode::K20 => -20.0,
            KMode::K14 => -14.0,
            KMode::K12 => -12.0,
        }
    }

    /// Convert dBFS to K-System reading
    pub fn dbfs_to_k(&self, dbfs: f64) -> f64 {
        dbfs - self.reference_level_dbfs()
    }
}
```

```rust
// crates/rf-dsp/src/metering/phase_scope.rs

/// Lissajous / Goniometer display data
pub struct PhaseScopeData {
    /// X-Y points for display (normalized -1..1)
    pub points: Vec<(f32, f32)>,
    /// Correlation coefficient (-1 to +1)
    pub correlation: f32,
    /// Phase angle (degrees)
    pub phase_angle: f32,
}

impl PhaseScope {
    /// Process stereo samples for Lissajous display
    pub fn process(&mut self, left: f64, right: f64) {
        // M/S encoding for display
        let mid = (left + right) * 0.5;
        let side = (left - right) * 0.5;

        // Lissajous: X = Side, Y = Mid
        self.points.push((side as f32, mid as f32));

        // Update correlation
        self.update_correlation(left, right);
    }
}
```

**Tasks:**

| Task | Fajl | Effort |
|------|------|--------|
| K-System meter | `rf-dsp/src/metering/k_system.rs` | S |
| Phase scope DSP | `rf-dsp/src/metering/phase_scope.rs` | M |
| Spectrogram DSP | `rf-dsp/src/metering/spectrogram.rs` | M |
| PSR calculation | `rf-dsp/src/metering/psr.rs` | S |
| K-System UI | `flutter_ui/.../k_system_meter.dart` | M |
| Phase scope UI (GPU) | `flutter_ui/.../phase_scope.dart` | L |
| Spectrogram UI (GPU) | `flutter_ui/.../spectrogram.dart` | L |
| FFI bindings | `rf-bridge/src/metering_ffi.rs` | M |

**Total effort:** ~3-4 nedelje

---

### 1.3 Hybrid Phase EQ (FabFilter Pro-Q Level)

**Šta konkurencija ima:**
- Cubase Frequency 2: 8 bands, dynamic, NO hybrid phase
- Logic Linear Phase EQ: Linear only, no hybrid
- Pro Tools EQ III: Minimum phase only
- REAPER ReaEQ: IIR only

**Naše rešenje — Per-band phase selection:**

```rust
// crates/rf-dsp/src/eq/hybrid_phase.rs

/// Per-band phase mode
#[derive(Debug, Clone, Copy)]
pub enum BandPhaseMode {
    /// Traditional IIR, zero latency
    MinimumPhase,
    /// FFT-based, no phase shift, high latency
    LinearPhase,
    /// Blend between minimum and linear
    Hybrid { blend: f64 }, // 0.0 = min, 1.0 = linear
    /// Natural phase (analog modeling)
    NaturalPhase,
}

pub struct HybridPhaseEQ {
    bands: Vec<HybridBand>,
    /// FFT size for linear phase processing
    fft_size: usize,
    /// Lookahead buffer for linear phase
    lookahead_buffer: Vec<f64>,
    /// Overall processing mode
    global_mode: GlobalPhaseMode,
}

pub struct HybridBand {
    /// Minimum phase IIR filter
    min_phase: BiquadTDF2,
    /// Linear phase FIR coefficients
    linear_fir: Vec<f64>,
    /// Current phase mode
    phase_mode: BandPhaseMode,
    /// Dynamic EQ parameters
    dynamics: Option<BandDynamics>,
}

pub struct BandDynamics {
    pub threshold_db: f64,
    pub ratio: f64,
    pub attack_ms: f64,
    pub release_ms: f64,
    /// Sidechain source (self or external)
    pub sidechain: SidechainSource,
}
```

**Features beyond Pro-Q:**

| Feature | FabFilter Pro-Q 3 | ReelForge Hybrid EQ |
|---------|------------------|---------------------|
| Bands | 24 | **64** |
| Phase modes | Min/Linear/Natural | Min/Linear/Hybrid/Natural |
| Per-band phase | ✅ | ✅ |
| Dynamic EQ | ✅ | ✅ |
| M/S processing | ✅ | ✅ |
| SIMD optimized | Unknown | **AVX-512** |
| GPU spectrum | ✅ | ✅ |
| Zero-latency mode | ✅ | ✅ |

**Tasks:**

| Task | Fajl | Effort |
|------|------|--------|
| Hybrid band struct | `rf-dsp/src/eq/hybrid_band.rs` | M |
| Phase mode blending | `rf-dsp/src/eq/phase_blend.rs` | L |
| Dynamic EQ per band | `rf-dsp/src/eq/dynamic_band.rs` | M |
| Natural phase model | `rf-dsp/src/eq/natural_phase.rs` | L |
| Zero-latency mode | `rf-dsp/src/eq/zero_latency.rs` | M |
| UI panel redesign | `flutter_ui/.../hybrid_eq_panel.dart` | XL |
| FFI bindings | `rf-bridge/src/hybrid_eq_ffi.rs` | M |

**Total effort:** ~4-5 nedelja

---

## PHASE 2: DIFFERENTIATION (2-4 meseca)

### 2.1 DSD/DXD Native Support

**Zašto je ovo važno:**
- Pyramix je JEDINI DAW sa native DSD
- Audiophile market ($$$)
- SACD mastering workflow
- Premium positioning

**Implementacija:**

```rust
// crates/rf-dsp/src/dsd/mod.rs

/// DSD sample rates
pub const DSD64_RATE: u32 = 2_822_400;   // 64 × 44100
pub const DSD128_RATE: u32 = 5_644_800;  // 128 × 44100
pub const DSD256_RATE: u32 = 11_289_600; // 256 × 44100
pub const DXD_RATE: u32 = 352_800;       // 8 × 44100

/// Sigma-Delta Modulator for PCM→DSD conversion
pub struct SigmaDeltaModulator {
    modulator_type: SdmType,
    /// Integrator states
    integrators: [f64; 5], // 5th order modulator
    /// Previous output
    prev_output: i8,
}

#[derive(Debug, Clone, Copy)]
pub enum SdmType {
    /// Original algorithm
    TypeB,
    /// Dithered, recommended default
    TypeD,
    /// Meco algorithm (Pyramix)
    TypeMeco,
}

/// DSD↔PCM converter
pub struct DsdConverter {
    /// Decimation filter for DSD→PCM
    decimation_filter: DecimationFilter,
    /// SDM for PCM→DSD
    modulator: SigmaDeltaModulator,
}

impl DsdConverter {
    /// Convert DSD to DXD (352.8kHz PCM) for editing
    pub fn dsd_to_dxd(&mut self, dsd_bits: &[u8]) -> Vec<f64> {
        // Multi-stage decimation
        // DSD64 (2.8MHz) → 705.6kHz → 352.8kHz (DXD)
        self.decimation_filter.process(dsd_bits)
    }

    /// Convert DXD back to DSD
    pub fn dxd_to_dsd(&mut self, dxd_samples: &[f64]) -> Vec<u8> {
        // Interpolate and modulate
        self.modulator.process(dxd_samples)
    }
}
```

**Workflow (kao Pyramix):**
1. Import DSD file
2. Automatically convert to DXD for editing
3. Only convert edited sections
4. Export back to DSD

**Tasks:**

| Task | Fajl | Effort |
|------|------|--------|
| DSD file reader (DSDIFF, DSF) | `rf-file/src/dsd_reader.rs` | L |
| Decimation filter | `rf-dsp/src/dsd/decimation.rs` | M |
| Sigma-Delta modulator | `rf-dsp/src/dsd/sdm.rs` | L |
| DXD editing mode | `rf-engine/src/dxd_mode.rs` | L |
| Selective conversion | `rf-engine/src/dsd_selective.rs` | M |
| DSD export | `rf-file/src/dsd_writer.rs` | L |
| UI indicators | `flutter_ui/.../dsd_indicator.dart` | S |

**Total effort:** ~6-8 nedelja

---

### 2.2 GPU-Accelerated DSP

**Zašto:**
- Massive parallelism
- Offload CPU za real-time
- Huge convolution IRs
- Real-time spectrogram

**wgpu Compute Shader za FFT:**

```wgsl
// shaders/fft_compute.wgsl

@group(0) @binding(0) var<storage, read> input: array<vec2<f32>>;
@group(0) @binding(1) var<storage, read_write> output: array<vec2<f32>>;
@group(0) @binding(2) var<uniform> params: FftParams;

struct FftParams {
    n: u32,
    inverse: u32,
    stage: u32,
}

@compute @workgroup_size(256)
fn fft_stage(@builtin(global_invocation_id) id: vec3<u32>) {
    let idx = id.x;
    if (idx >= params.n) { return; }

    // Cooley-Tukey butterfly
    let stage_size = 1u << params.stage;
    let half_stage = stage_size >> 1u;

    let pair_idx = (idx / stage_size) * stage_size + (idx % half_stage);
    let partner = pair_idx + half_stage;

    // Twiddle factor
    let angle = -2.0 * 3.14159265359 * f32(idx % half_stage) / f32(stage_size);
    let twiddle = vec2<f32>(cos(angle), sin(angle));

    // Butterfly operation
    let a = input[pair_idx];
    let b_raw = input[partner];
    let b = vec2<f32>(
        b_raw.x * twiddle.x - b_raw.y * twiddle.y,
        b_raw.x * twiddle.y + b_raw.y * twiddle.x
    );

    output[pair_idx] = a + b;
    output[partner] = a - b;
}
```

**Tasks:**

| Task | Fajl | Effort |
|------|------|--------|
| wgpu compute pipeline | `rf-viz/src/compute/mod.rs` | L |
| FFT compute shader | `shaders/fft_compute.wgsl` | L |
| Convolution compute | `shaders/convolution.wgsl` | L |
| Spectrogram compute | `shaders/spectrogram.wgsl` | M |
| CPU↔GPU transfer | `rf-viz/src/compute/transfer.rs` | M |
| Fallback to CPU | `rf-viz/src/compute/fallback.rs` | M |

**Total effort:** ~6-8 nedelja

---

## PHASE 3: GAME CHANGERS (4-8 meseci)

### 3.1 AI-Powered Processing

**Rust ML Options:**
- `tract` - ONNX runtime, fast inference
- `candle` - Hugging Face, PyTorch-like
- `tch-rs` - PyTorch bindings

**Features:**

| Feature | Model | Effort |
|---------|-------|--------|
| Noise reduction | RNNoise / DeepFilterNet | L |
| EQ matching | Custom CNN | XL |
| Stem separation | Demucs / Spleeter | XL |
| Mastering assistant | Custom | XL |
| Auto gain staging | Simple DNN | M |
| Chord detection | Transformer | L |

**Example Implementation:**

```rust
// crates/rf-ml/src/noise_reduction.rs

use tract_onnx::prelude::*;

pub struct NeuralDenoiser {
    model: SimplePlan<TypedFact, Box<dyn TypedOp>, Graph<TypedFact, Box<dyn TypedOp>>>,
    hop_size: usize,
    frame_size: usize,
}

impl NeuralDenoiser {
    pub fn load(model_path: &str) -> Result<Self> {
        let model = tract_onnx::onnx()
            .model_for_path(model_path)?
            .into_optimized()?
            .into_runnable()?;

        Ok(Self {
            model,
            hop_size: 480,
            frame_size: 960,
        })
    }

    pub fn process_frame(&mut self, noisy: &[f32]) -> Vec<f32> {
        let input = tract_ndarray::Array2::from_shape_vec(
            (1, self.frame_size),
            noisy.to_vec()
        ).unwrap();

        let result = self.model.run(tvec!(input.into())).unwrap();
        result[0].to_array_view::<f32>().unwrap().to_vec()
    }
}
```

**Total effort:** ~3-6 meseci za full suite

---

### 3.2 Dolby Atmos Native

**Šta treba:**
- 7.1.2 / 7.1.4 bed tracks
- Up to 118 audio objects
- 3D object panner
- Binaural rendering
- ADM BWF export

**Složenost:** XL (3-4 meseca)

---

## PRIORITIZED IMPLEMENTATION ORDER

| Phase | Feature | Effort | Timeline | Unique Value |
|-------|---------|--------|----------|--------------|
| **1.1** | Sample-Accurate Auto | M | 2-3 weeks | Only DAW with true sample-accurate |
| **1.2** | K-System + Phase Scope | M | 3-4 weeks | Complete mastering metering |
| **1.3** | Hybrid Phase EQ | L | 4-5 weeks | FabFilter-level, native |
| **2.1** | DSD/DXD Native | L | 6-8 weeks | Only Rust DAW with DSD |
| **2.2** | GPU DSP | L | 6-8 weeks | Revolutionary |
| **3.1** | AI Noise Reduction | L | 4-6 weeks | Modern expectation |
| **3.2** | Dolby Atmos | XL | 3-4 months | Professional requirement |

---

## SUCCESS METRICS

### Po završetku Phase 1:
- [ ] Sample-accurate automation demonstrable
- [ ] K-System metering functional
- [ ] Phase scope GPU rendered
- [ ] Hybrid Phase EQ sa 64 bands

### Po završetku Phase 2:
- [ ] DSD64/128/256 playback
- [ ] DXD editing workflow
- [ ] GPU spectrum analyzer 60fps
- [ ] GPU convolution working

### Po završetku Phase 3:
- [ ] AI noise reduction < 10ms latency
- [ ] Stem separation working
- [ ] Dolby Atmos export validated
- [ ] Full ADM BWF compliance

---

## COMPETITIVE POSITIONING

Po završetku svih faza:

| Category | Winner |
|----------|--------|
| **Sample-Accurate Automation** | **ReelForge** ✅ |
| **Native DSP Quality** | **ReelForge** ✅ |
| **Spectral Processing** | **ReelForge** ✅ |
| **Modern Architecture** | **ReelForge** ✅ |
| **DSD Support** | Pyramix = ReelForge |
| **GPU Acceleration** | **ReelForge** ✅ |
| **AI Processing** | Logic ≈ ReelForge |
| **Dolby Atmos** | Logic/PT ≈ ReelForge |

---

*Poslednje ažuriranje: 2025-01-08*
*Reference: `.claude/analysis/dsp-competitive-analysis.md`*

# Audio & DSP Domain — Rust Native

> Učitaj ovaj fajl kada radiš: DSP processors, audio I/O, real-time audio, SIMD optimization.

---

## Uloge

- **Chief Audio Architect** — pipeline dizajn, audio graph
- **Lead DSP Engineer** — filters, dynamics, SIMD, real-time
- **Audio Integration Specialist** — plugin hosting, format support

---

## Core Principles

1. **Zero Allocation in Audio Thread** — pre-allocate everything
2. **Lock-Free Communication** — rtrb ring buffers
3. **SIMD First** — AVX-512/AVX2/SSE4.2/NEON
4. **64-bit Precision** — f64 internal, f32 I/O only
5. **Deterministic** — same input = same output, always

---

## Audio Thread Rules

```rust
// ═══════════════════════════════════════════════════════════════
// AUDIO CALLBACK — SACRED GROUND
// ═══════════════════════════════════════════════════════════════

// ❌ FORBIDDEN:
fn audio_callback_bad(buffer: &mut [f32]) {
    let vec = Vec::new();           // ❌ Heap allocation
    let string = format!("{}", x);  // ❌ Heap allocation
    mutex.lock();                   // ❌ Can block
    println!("debug");              // ❌ System call
    file.read();                    // ❌ I/O
    result.unwrap();                // ❌ Can panic
}

// ✅ ALLOWED:
fn audio_callback_good(buffer: &mut [f32], state: &mut ProcessState) {
    // Stack allocation only
    let temp: [f64; 256] = [0.0; 256];

    // Pre-allocated buffers
    state.scratch_buffer.copy_from_slice(buffer);

    // Atomics for communication
    let gain = state.gain.load(Ordering::Relaxed);

    // SIMD processing
    process_simd(&mut state.scratch_buffer);

    // Lock-free parameter reads
    while let Ok(param) = state.param_consumer.pop() {
        state.apply_param(param);
    }
}
```

---

## SIMD Patterns

### Runtime Dispatch

```rust
use std::arch::x86_64::*;

pub fn process_block(samples: &mut [f64]) {
    #[cfg(target_arch = "x86_64")]
    {
        if is_x86_feature_detected!("avx512f") {
            unsafe { process_avx512(samples) }
        } else if is_x86_feature_detected!("avx2") {
            unsafe { process_avx2(samples) }
        } else if is_x86_feature_detected!("sse4.2") {
            unsafe { process_sse42(samples) }
        } else {
            process_scalar(samples)
        }
    }

    #[cfg(target_arch = "aarch64")]
    {
        unsafe { process_neon(samples) }
    }
}
```

### AVX2 Example — Gain

```rust
#[target_feature(enable = "avx2")]
unsafe fn apply_gain_avx2(samples: &mut [f64], gain: f64) {
    let gain_vec = _mm256_set1_pd(gain);

    for chunk in samples.chunks_exact_mut(4) {
        let input = _mm256_loadu_pd(chunk.as_ptr());
        let output = _mm256_mul_pd(input, gain_vec);
        _mm256_storeu_pd(chunk.as_mut_ptr(), output);
    }

    // Handle remainder
    let remainder = samples.len() % 4;
    if remainder > 0 {
        let start = samples.len() - remainder;
        for sample in &mut samples[start..] {
            *sample *= gain;
        }
    }
}
```

### AVX-512 Example — Biquad

```rust
#[target_feature(enable = "avx512f")]
unsafe fn process_biquad_avx512(
    samples: &mut [f64],
    coeffs: &BiquadCoeffs,
    state: &mut BiquadState,
) {
    // Process 8 samples at once with AVX-512
    let b0 = _mm512_set1_pd(coeffs.b0);
    let b1 = _mm512_set1_pd(coeffs.b1);
    let b2 = _mm512_set1_pd(coeffs.b2);
    let a1 = _mm512_set1_pd(coeffs.a1);
    let a2 = _mm512_set1_pd(coeffs.a2);

    // ... processing loop
}
```

---

## Biquad Filters

### TDF-II Structure (Recommended)

```rust
/// Transposed Direct Form II — numerically optimal
pub struct BiquadTDF2 {
    // Coefficients
    b0: f64, b1: f64, b2: f64,
    a1: f64, a2: f64,
    // State
    z1: f64, z2: f64,
}

impl BiquadTDF2 {
    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        let output = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * output + self.z2;
        self.z2 = self.b2 * input - self.a2 * output;
        output
    }

    pub fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }
}
```

### Coefficient Calculation — Matched Z-Transform

```rust
/// Vicanek's matched Z-transform for better analog matching
pub fn bell_matched(freq: f64, gain_db: f64, q: f64, sample_rate: f64) -> BiquadCoeffs {
    let w0 = 2.0 * PI * freq / sample_rate;
    let a = 10.0_f64.powf(gain_db / 40.0);
    let alpha = (w0 / 2.0).sin() / (2.0 * q);

    let cos_w0 = w0.cos();

    let b0 = 1.0 + alpha * a;
    let b1 = -2.0 * cos_w0;
    let b2 = 1.0 - alpha * a;
    let a0 = 1.0 + alpha / a;
    let a1 = -2.0 * cos_w0;
    let a2 = 1.0 - alpha / a;

    BiquadCoeffs {
        b0: b0 / a0,
        b1: b1 / a0,
        b2: b2 / a0,
        a1: a1 / a0,
        a2: a2 / a0,
    }
}
```

### Filter Types

```rust
pub enum FilterType {
    Bell,           // Parametric EQ
    LowShelf,       // Bass boost/cut
    HighShelf,      // Treble boost/cut
    LowPass,        // High cut
    HighPass,       // Low cut
    BandPass,       // Pass band only
    Notch,          // Band reject
    AllPass,        // Phase shift only
    Tilt,           // Spectral tilt
}
```

---

## Lock-Free Communication

### Parameter Changes (UI → Audio)

```rust
use rtrb::{Consumer, Producer, RingBuffer};

pub struct ParamChange {
    pub id: u32,
    pub value: f64,
}

pub struct AudioProcessor {
    param_consumer: Consumer<ParamChange>,
    // ... other fields
}

impl AudioProcessor {
    pub fn process(&mut self, buffer: &mut [f32]) {
        // Drain all pending parameter changes (non-blocking)
        while let Ok(change) = self.param_consumer.pop() {
            self.apply_param(change);
        }

        // Process audio
        self.process_audio(buffer);
    }
}
```

### Meter Data (Audio → UI)

```rust
pub struct MeterData {
    pub peak_l: f32,
    pub peak_r: f32,
    pub rms_l: f32,
    pub rms_r: f32,
}

pub struct AudioProcessor {
    meter_producer: Producer<MeterData>,
    // ...
}

impl AudioProcessor {
    pub fn process(&mut self, buffer: &mut [f32]) {
        // Calculate meters
        let meter = self.calculate_meters(buffer);

        // Send to UI (non-blocking, drop if full)
        let _ = self.meter_producer.push(meter);
    }
}
```

---

## FFT Analysis

### Real FFT with rustfft

```rust
use realfft::{RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;

pub struct SpectrumAnalyzer {
    fft: Arc<dyn RealToComplex<f64>>,
    input_buffer: Vec<f64>,
    output_buffer: Vec<Complex<f64>>,
    window: Vec<f64>,
    fft_size: usize,
}

impl SpectrumAnalyzer {
    pub fn new(fft_size: usize) -> Self {
        let mut planner = RealFftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);

        Self {
            fft,
            input_buffer: vec![0.0; fft_size],
            output_buffer: vec![Complex::default(); fft_size / 2 + 1],
            window: hann_window(fft_size),
            fft_size,
        }
    }

    pub fn process(&mut self, samples: &[f64]) -> &[Complex<f64>] {
        // Apply window
        for (i, sample) in samples.iter().enumerate() {
            self.input_buffer[i] = sample * self.window[i];
        }

        // Compute FFT
        self.fft.process(&mut self.input_buffer, &mut self.output_buffer).unwrap();

        &self.output_buffer
    }
}

fn hann_window(size: usize) -> Vec<f64> {
    (0..size)
        .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / size as f64).cos()))
        .collect()
}
```

---

## Oversampling

```rust
pub struct Oversampler {
    factor: usize,  // 2, 4, 8, or 16
    upsample_filter: FirFilter,
    downsample_filter: FirFilter,
    upsampled_buffer: Vec<f64>,
}

impl Oversampler {
    pub fn process<F>(&mut self, samples: &mut [f64], processor: F)
    where
        F: FnMut(&mut [f64]),
    {
        // Upsample
        self.upsample(samples, &mut self.upsampled_buffer);

        // Process at higher rate
        processor(&mut self.upsampled_buffer);

        // Downsample
        self.downsample(&self.upsampled_buffer, samples);
    }
}
```

---

## Denormal Prevention

```rust
/// Call at start of audio callback
pub fn flush_denormals() {
    #[cfg(target_arch = "x86_64")]
    unsafe {
        use std::arch::x86_64::*;
        _MM_SET_FLUSH_ZERO_MODE(_MM_FLUSH_ZERO_ON);
        _MM_SET_DENORMALS_ZERO_MODE(_MM_DENORMALS_ZERO_ON);
    }
}

/// Alternative: add tiny DC offset
const DENORMAL_OFFSET: f64 = 1e-25;

fn prevent_denormal(x: f64) -> f64 {
    x + DENORMAL_OFFSET
}
```

---

## Metering

### True Peak (ITU-R BS.1770-4)

```rust
pub struct TruePeakMeter {
    oversampler: Oversampler4x,
    peak: f64,
}

impl TruePeakMeter {
    pub fn process(&mut self, samples: &[f64]) -> f64 {
        // Oversample 4x for true peak detection
        let oversampled = self.oversampler.process(samples);

        for sample in oversampled {
            let abs = sample.abs();
            if abs > self.peak {
                self.peak = abs;
            }
        }

        self.peak
    }
}
```

### LUFS (EBU R128)

```rust
pub struct LufsMeter {
    k_filter: KWeightingFilter,
    gate_buffer: CircularBuffer<f64>,
    // ...
}

impl LufsMeter {
    pub fn momentary(&self) -> f64 {
        // 400ms window
        self.calculate_loudness(400)
    }

    pub fn short_term(&self) -> f64 {
        // 3s window
        self.calculate_loudness(3000)
    }

    pub fn integrated(&self) -> f64 {
        // Gated, from start
        self.calculate_gated_loudness()
    }
}
```

---

## Audio I/O with cpal

```rust
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

pub fn create_audio_stream(
    processor: Arc<Mutex<AudioProcessor>>,
) -> Result<cpal::Stream, cpal::BuildStreamError> {
    let host = cpal::default_host();
    let device = host.default_output_device().unwrap();

    let config = cpal::StreamConfig {
        channels: 2,
        sample_rate: cpal::SampleRate(44100),
        buffer_size: cpal::BufferSize::Fixed(128),
    };

    device.build_output_stream(
        &config,
        move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
            // Lock-free would be better, but for now:
            if let Ok(mut proc) = processor.try_lock() {
                proc.process(data);
            }
        },
        |err| eprintln!("Audio error: {}", err),
        None,
    )
}
```

---

## Checklist

- [ ] No allocations in audio callback
- [ ] SIMD for all DSP operations
- [ ] Lock-free UI ↔ Audio communication
- [ ] 64-bit internal precision
- [ ] Denormal prevention active
- [ ] True peak metering
- [ ] All filters tested against reference

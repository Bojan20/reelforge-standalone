# Engine & Architecture Domain — Rust Native

> Učitaj ovaj fajl kada radiš: performance optimization, memory management, system architecture, concurrency.

---

## Uloge

- **Engine Architect** — system design, modularity, scalability
- **Performance Engineer** — optimization, memory, CPU, GPU
- **Security Expert** — input validation, safe Rust patterns

---

## Core Principles

1. **Zero-Cost Abstractions** — use Rust's type system
2. **Fearless Concurrency** — no data races by design
3. **Explicit over Implicit** — no hidden allocations
4. **Fail Fast** — validate early, propagate errors
5. **Measure First** — profile before optimizing

---

## Memory Patterns

### Pre-allocation

```rust
/// Pre-allocate all buffers at initialization
pub struct AudioEngine {
    // Fixed-size buffers, allocated once
    scratch_l: Box<[f64; MAX_BUFFER_SIZE]>,
    scratch_r: Box<[f64; MAX_BUFFER_SIZE]>,
    fft_buffer: Box<[Complex<f64>; FFT_SIZE]>,

    // Pool for dynamic needs
    buffer_pool: BufferPool,
}

impl AudioEngine {
    pub fn new() -> Self {
        Self {
            scratch_l: Box::new([0.0; MAX_BUFFER_SIZE]),
            scratch_r: Box::new([0.0; MAX_BUFFER_SIZE]),
            fft_buffer: Box::new([Complex::default(); FFT_SIZE]),
            buffer_pool: BufferPool::new(16, MAX_BUFFER_SIZE),
        }
    }
}
```

### Object Pooling

```rust
pub struct BufferPool {
    buffers: Vec<Vec<f64>>,
    available: Vec<usize>,
}

impl BufferPool {
    pub fn new(count: usize, size: usize) -> Self {
        let buffers = (0..count).map(|_| vec![0.0; size]).collect();
        let available = (0..count).collect();
        Self { buffers, available }
    }

    pub fn acquire(&mut self) -> Option<&mut [f64]> {
        self.available.pop().map(|i| self.buffers[i].as_mut_slice())
    }

    pub fn release(&mut self, index: usize) {
        // Clear and return to pool
        self.buffers[index].fill(0.0);
        self.available.push(index);
    }
}
```

### Aligned Memory for SIMD

```rust
#[repr(C, align(64))]  // Cache line aligned
pub struct AlignedBuffer {
    data: [f64; 1024],
}

// Or use aligned_vec crate
use aligned_vec::AVec;
let buffer: AVec<f64, aligned_vec::ConstAlign<64>> = AVec::new(64);
```

---

## Concurrency Patterns

### Lock-Free Ring Buffer

```rust
use rtrb::RingBuffer;

// Create channel
let (mut producer, mut consumer) = RingBuffer::<Message>::new(1024);

// Producer (UI thread)
fn send_param(&mut self, id: u32, value: f64) {
    let msg = Message::ParamChange { id, value };
    // Non-blocking, drops if full
    let _ = self.producer.push(msg);
}

// Consumer (Audio thread)
fn process_messages(&mut self) {
    while let Ok(msg) = self.consumer.pop() {
        match msg {
            Message::ParamChange { id, value } => {
                self.params[id as usize] = value;
            }
            // ...
        }
    }
}
```

### Atomic State

```rust
use std::sync::atomic::{AtomicU64, Ordering};

pub struct AtomicParam {
    bits: AtomicU64,
}

impl AtomicParam {
    pub fn get(&self) -> f64 {
        f64::from_bits(self.bits.load(Ordering::Relaxed))
    }

    pub fn set(&self, value: f64) {
        self.bits.store(value.to_bits(), Ordering::Relaxed);
    }
}
```

### Parallel Processing with Rayon

```rust
use rayon::prelude::*;

// Only for non-real-time operations!
fn parallel_analysis(tracks: &mut [Track]) {
    tracks.par_iter_mut().for_each(|track| {
        track.analyze_loudness();
    });
}
```

---

## Error Handling

### Custom Error Types

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AudioError {
    #[error("Buffer size {0} exceeds maximum {1}")]
    BufferTooLarge(usize, usize),

    #[error("Sample rate {0} not supported")]
    UnsupportedSampleRate(u32),

    #[error("Device not found: {0}")]
    DeviceNotFound(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, AudioError>;
```

### No Panics in Audio Thread

```rust
// ❌ BAD — can panic
fn bad_process(buffer: &mut [f32]) {
    let value = some_option.unwrap();  // Panic!
    let item = vec[index];             // Panic if out of bounds!
}

// ✅ GOOD — graceful handling
fn good_process(buffer: &mut [f32]) {
    let value = some_option.unwrap_or(default);
    let item = vec.get(index).copied().unwrap_or(0.0);
}
```

---

## Performance Patterns

### Avoid in Hot Paths

```rust
// ❌ O(n) — shifts all elements
vec.remove(0);
vec.insert(0, item);

// ✅ O(1) — use VecDeque or circular buffer
use std::collections::VecDeque;
deque.pop_front();
deque.push_back(item);

// ❌ Allocates new array
let new_vec: Vec<_> = old_vec.iter().map(|x| x * 2.0).collect();

// ✅ In-place modification
for x in &mut vec {
    *x *= 2.0;
}

// ❌ Clone heavy data
let copy = large_struct.clone();

// ✅ Use references or Cow
fn process(data: &LargeStruct) { ... }
```

### Branch Prediction

```rust
// ❌ Unpredictable branches in loop
for sample in samples {
    if random_condition() {  // Unpredictable
        process_a(sample);
    } else {
        process_b(sample);
    }
}

// ✅ Batch by condition
let (a_samples, b_samples): (Vec<_>, Vec<_>) = samples
    .iter()
    .partition(|s| condition(s));
process_batch_a(&a_samples);
process_batch_b(&b_samples);
```

### Cache Efficiency

```rust
// ❌ Bad cache access pattern (column-major on row-major data)
for col in 0..width {
    for row in 0..height {
        matrix[row][col] *= 2.0;  // Cache miss each iteration
    }
}

// ✅ Good cache access pattern (row-major)
for row in 0..height {
    for col in 0..width {
        matrix[row][col] *= 2.0;  // Sequential access
    }
}
```

---

## Input Validation

### Validate Early

```rust
pub fn set_frequency(&mut self, freq: f64) -> Result<()> {
    // Validate
    if !freq.is_finite() {
        return Err(AudioError::InvalidParameter("frequency must be finite"));
    }
    if freq < 20.0 || freq > 20000.0 {
        return Err(AudioError::OutOfRange("frequency", 20.0, 20000.0));
    }

    // Apply
    self.frequency = freq;
    self.recalculate_coefficients();
    Ok(())
}
```

### Sanitize Paths

```rust
use std::path::Path;

pub fn load_preset(path: &Path) -> Result<Preset> {
    // Prevent path traversal
    let canonical = path.canonicalize()?;
    if !canonical.starts_with(&self.presets_dir) {
        return Err(AudioError::SecurityViolation("path traversal attempt"));
    }

    // Load file
    let data = std::fs::read(&canonical)?;
    serde_json::from_slice(&data).map_err(Into::into)
}
```

---

## Benchmarking

### Criterion Setup

```rust
// benches/dsp_benchmark.rs
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_biquad(c: &mut Criterion) {
    let mut filter = BiquadTDF2::bell(1000.0, 6.0, 1.0, 44100.0);
    let mut buffer = vec![0.5; 1024];

    c.bench_function("biquad_1024_samples", |b| {
        b.iter(|| {
            for sample in buffer.iter_mut() {
                *sample = filter.process(black_box(*sample));
            }
        })
    });
}

criterion_group!(benches, bench_biquad);
criterion_main!(benches);
```

### Profiling

```bash
# CPU profiling with samply (macOS)
cargo build --release
samply record ./target/release/reelforge

# Memory profiling with heaptrack
heaptrack ./target/release/reelforge

# Flamegraph
cargo flamegraph --bin reelforge
```

---

## Build Optimization

### Cargo.toml

```toml
[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"
strip = true

[profile.release.build-override]
opt-level = 3

# For development with some optimizations
[profile.dev-opt]
inherits = "dev"
opt-level = 2
```

### .cargo/config.toml

```toml
[build]
rustflags = ["-C", "target-cpu=native"]

[target.x86_64-apple-darwin]
rustflags = ["-C", "target-cpu=native", "-C", "link-arg=-undefined", "-C", "link-arg=dynamic_lookup"]

[target.aarch64-apple-darwin]
rustflags = ["-C", "target-cpu=native"]
```

### rust-toolchain.toml

```toml
[toolchain]
channel = "nightly"
components = ["rust-src", "clippy", "rustfmt"]
targets = ["x86_64-apple-darwin", "aarch64-apple-darwin", "x86_64-pc-windows-msvc"]
```

---

## Testing Patterns

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use approx::assert_relative_eq;

    #[test]
    fn test_biquad_dc_response() {
        let mut filter = BiquadTDF2::bell(1000.0, 0.0, 1.0, 44100.0);

        // DC input should pass through unchanged
        for _ in 0..1000 {
            let output = filter.process(1.0);
        }
        assert_relative_eq!(filter.process(1.0), 1.0, epsilon = 1e-10);
    }

    #[test]
    fn test_biquad_stability() {
        let mut filter = BiquadTDF2::bell(1000.0, 12.0, 10.0, 44100.0);

        // Should not explode with impulse
        filter.process(1.0);
        for _ in 0..10000 {
            let output = filter.process(0.0);
            assert!(output.is_finite());
            assert!(output.abs() < 100.0);
        }
    }
}
```

### Property-Based Testing

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn test_gain_range(gain in -60.0..12.0f64) {
        let mut processor = GainProcessor::new();
        processor.set_gain_db(gain);

        let input = vec![0.5; 1024];
        let output = processor.process(&input);

        for sample in output {
            prop_assert!(sample.is_finite());
        }
    }
}
```

---

## Logging

### Structured Logging

```rust
use log::{debug, error, info, trace, warn};

pub fn initialize_logging() {
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("info")
    )
    .format_timestamp_millis()
    .init();
}

// Usage
info!("Audio engine started: sample_rate={}, buffer_size={}", sr, bs);
debug!("Processing block {}", block_count);
warn!("Buffer underrun detected");
error!("Failed to open device: {}", err);

// NEVER in audio thread!
// Use lock-free logging if needed
```

---

## 🚀 Performance Optimization Guide

**Detaljni guide:** `.claude/performance/OPTIMIZATION_GUIDE.md`
**Cleanup checklist:** `.claude/performance/CODE_CLEANUP_CHECKLIST.md`

### Critical Issues (Fix ASAP)

#### 1. RwLock in Audio Thread → AtomicU8
**File:** `rf-audio/src/engine.rs:166-172, 341`
**Problem:** `transport.state.read()` blocks audio thread during UI writes
**Fix:** Replace `RwLock<TransportState>` with `AtomicU8`
**Gain:** 2-3ms latency reduction, zero dropouts

```rust
// Before (BLOCKING):
pub struct Transport {
    state: RwLock<TransportState>,  // ❌
}

// After (LOCK-FREE):
pub struct Transport {
    state: AtomicU8,  // ✅
}

impl Transport {
    #[inline]
    pub fn state(&self) -> TransportState {
        TransportState::from_u8(self.state.load(Ordering::Relaxed))
    }
}
```

---

#### 2. Vec Allocation in EQ Parameter Update
**File:** `rf-dsp/src/eq.rs:190-191`
**Problem:** `vec![BiquadTDF2::new()]` heap alloc on EVERY parameter change
**Fix:** Pre-allocate filter array, use dirty-bit caching
**Gain:** 3-5% CPU, zero latency spikes

```rust
// Before (HEAP ALLOC):
pub fn set_params(&mut self, freq: f64, ...) {
    self.filters_l = vec![BiquadTDF2::new(sr)];  // ❌ Alloc
}

// After (PRE-ALLOCATED):
pub struct EqBand {
    filters_l: [BiquadTDF2; 8],  // ✅ Stack array
    num_stages: usize,
    last_freq: f64,  // Cache for early exit
}

pub fn set_params(&mut self, freq: f64, ...) {
    if freq == self.last_freq { return; }  // Cache hit
    self.last_freq = freq;

    // Only update active stages
    for i in 0..self.num_stages {
        self.filters_l[i].update_coeffs(...);
    }
}
```

---

#### 3. Metering Over-Computation
**File:** `rf-audio/src/engine.rs:369-395`
**Problem:** Redundant abs() + full RMS on every callback
**Fix:** SIMD single-pass peak+RMS
**Gain:** 3-5% CPU in metering

```rust
// Before (SCALAR, REDUNDANT):
for i in 0..frames {
    let l = left_buf[i].abs();    // ❌ 2× abs per sample
    let r = right_buf[i].abs();
    peak_l = peak_l.max(l);
    sum_sq_l += left_buf[i] * left_buf[i];  // ❌ Full RMS
}

// After (SIMD OPTIMIZED):
use std::simd::f64x4;

let mut peak = f64x4::splat(0.0);
let mut sum_sq = f64x4::splat(0.0);

for chunk in samples.chunks_exact(4) {
    let vals = f64x4::from_slice(chunk);
    let abs_vals = vals.abs();
    peak = peak.simd_max(abs_vals);
    sum_sq += vals * vals;  // Single pass
}
```

---

#### 4. Biquad SIMD Without Runtime Dispatch
**File:** `rf-dsp/src/biquad.rs:494-528`
**Problem:** Hardcoded f64x4, no AVX-512 (8-lane) support
**Fix:** Runtime CPU detection + AVX-512 path
**Gain:** 15-30% faster filtering on modern CPUs

```rust
// Before (FIXED 4-LANE):
pub fn process_block(&mut self, buffer: &mut [Sample]) {
    for i in (0..simd_len).step_by(4) {  // ❌ Always 4
        let input = f64x4::from_slice(&buffer[i..]);
        // ...
    }
}

// After (RUNTIME DISPATCH):
pub fn process_block(&mut self, buffer: &mut [Sample]) {
    #[cfg(target_arch = "x86_64")]
    {
        if is_x86_feature_detected!("avx512f") {
            unsafe { self.process_avx512(buffer) }  // ✅ 8-lane
        } else if is_x86_feature_detected!("avx2") {
            unsafe { self.process_avx2(buffer) }    // ✅ 4-lane
        } else {
            self.process_scalar_loop(buffer)
        }
    }
}
```

---

### Quick Wins Checklist

| Priority | Issue | File:Line | Effort | Gain |
|----------|-------|-----------|--------|------|
| 🔴 1 | RwLock audio thread | engine.rs:166 | 30min | 2-3ms latency |
| 🔴 2 | EQ Vec alloc | eq.rs:190 | 45min | 3-5% CPU |
| 🔴 3 | Peak decay pre-compute | engine.rs:323 | 5min | 0.5% CPU |
| 🟠 4 | Biquad AVX-512 | biquad.rs:494 | 2h | 20-30% filter |
| 🟠 5 | Dynamics SIMD | dynamics.rs:45 | 1.5h | 1-2% CPU |
| 🟡 6 | Waveform LOD cache | waveform.rs:147 | 1h | 30-50% import |

---

### Anti-Patterns Discovered

❌ **NEVER do this:**
1. Locks in audio thread (RwLock, Mutex) → Use Atomic
2. Vec::push in hot path → Pre-allocate
3. Redundant log10/pow → Lookup tables
4. Branch per-sample → SIMD branchless
5. Intermediate Vec in loop → Direct compute
6. Clone heavy structs → Use &references

✅ **ALWAYS do this:**
1. Profile BEFORE optimizing
2. Benchmark BEFORE and AFTER
3. Test audio playback after changes
4. Verify zero allocations in hot paths

---

## Checklist

### Performance
- [ ] No allocations in hot paths
- [ ] SIMD utilized where applicable
- [ ] Cache-friendly data layout
- [ ] Profiled with real workload

### Safety
- [ ] No panics in audio thread
- [ ] All inputs validated
- [ ] Errors propagated properly
- [ ] No undefined behavior

### Quality
- [ ] Unit tests for all DSP
- [ ] Integration tests
- [ ] Benchmarks for critical paths
- [ ] Documentation complete

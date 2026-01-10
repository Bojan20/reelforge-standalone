# Real-Time Audio Performance Patterns

**Reference Guide for Professional Audio Software**

> Patterns used in DAWs like Cubase, Pro Tools, Pyramix, and plugin developers like FabFilter, iZotope.

---

## Table of Contents

1. [Lock-Free Programming Patterns](#1-lock-free-programming-patterns)
2. [Memory Management](#2-memory-management)
3. [Threading Models](#3-threading-models)
4. [SIMD Optimization](#4-simd-optimization)
5. [Latency Management](#5-latency-management)
6. [Quick Reference](#6-quick-reference)

---

## 1. Lock-Free Programming Patterns

### 1.1 The Golden Rule

**NEVER block the audio thread.** Any blocking operation (mutex, syscall, heap allocation) can cause audio dropouts (glitches). At 48kHz with 128-sample buffer, you have **2.67ms** to process all audio.

```rust
// FORBIDDEN in audio callback:
fn audio_callback_bad(buffer: &mut [f32]) {
    mutex.lock();                // Can block indefinitely
    let v = Vec::new();          // Heap allocation
    println!("debug");           // System call
    file.read();                 // I/O
    result.unwrap();             // Can panic
}

// ALLOWED in audio callback:
fn audio_callback_good(buffer: &mut [f32], state: &mut ProcessState) {
    let gain = state.gain.load(Ordering::Relaxed);  // Atomic read
    while let Ok(param) = state.param_rx.pop() {    // Lock-free queue
        state.apply_param(param);
    }
    process_simd(buffer, gain);  // Stack + SIMD only
}
```

### 1.2 Ring Buffers (SPSC - Single Producer Single Consumer)

The most common pattern for UI-to-audio communication. One thread writes, one thread reads, no locks needed.

```rust
use rtrb::{Consumer, Producer, RingBuffer};

pub struct ParamChange {
    pub id: u32,
    pub value: f64,
    pub sample_offset: u32,      // For sample-accurate automation
    pub smoothing_samples: u32,  // Parameter smoothing
}

// Creation (at init time, not audio time)
let (producer, consumer) = RingBuffer::<ParamChange>::new(1024);

// UI Thread (Producer)
fn send_param_change(producer: &mut Producer<ParamChange>, id: u32, value: f64) {
    let _ = producer.push(ParamChange {
        id,
        value,
        sample_offset: 0,
        smoothing_samples: 64,
    });
    // Non-blocking: if queue full, change is dropped (acceptable for UI)
}

// Audio Thread (Consumer)
fn process_param_changes(consumer: &mut Consumer<ParamChange>, params: &mut [f64]) {
    while let Ok(change) = consumer.pop() {
        // Non-blocking: returns immediately if empty
        params[change.id as usize] = change.value;
    }
}
```

**Implementation Notes:**
- `rtrb` crate provides wait-free SPSC queue
- Queue size should be 2-4x expected max burst (1024 is typical)
- Always check capacity during development (queue overflow = lost messages)

### 1.3 MPSC (Multiple Producer Single Consumer)

For multiple UI threads or worker threads sending to audio.

```rust
use crossbeam_channel::{bounded, Receiver, Sender, TrySendError};

// Bounded channel prevents memory explosion
let (tx, rx) = bounded::<AudioCommand>(256);

// Any thread can send (clone the sender)
let tx2 = tx.clone();

// Audio thread receives without blocking
fn process_commands(rx: &Receiver<AudioCommand>) {
    while let Ok(cmd) = rx.try_recv() {
        match cmd {
            AudioCommand::SetGain(g) => { /* ... */ }
            AudioCommand::Stop => { /* ... */ }
        }
    }
}
```

### 1.4 Triple Buffering

For sharing complex state (presets, automation data) without blocking.

```
Write Buffer ──> Ready Buffer ──> Read Buffer
   (UI)           (swap zone)       (Audio)
```

```rust
use std::sync::atomic::{AtomicU32, Ordering};
use std::cell::UnsafeCell;

pub struct TripleBuffer<T> {
    buffers: [UnsafeCell<T>; 3],
    // Bit layout: [write_idx: 2][ready_idx: 2][read_idx: 2]
    state: AtomicU32,
}

unsafe impl<T: Send> Send for TripleBuffer<T> {}
unsafe impl<T: Send> Sync for TripleBuffer<T> {}

impl<T: Clone + Default> TripleBuffer<T> {
    pub fn new(initial: T) -> Self {
        Self {
            buffers: [
                UnsafeCell::new(initial.clone()),
                UnsafeCell::new(initial.clone()),
                UnsafeCell::new(initial),
            ],
            state: AtomicU32::new(0b00_01_10), // write=0, ready=1, read=2
        }
    }

    // Producer side (UI thread)
    pub fn write(&self) -> &mut T {
        let state = self.state.load(Ordering::Acquire);
        let write_idx = (state & 0b11) as usize;
        unsafe { &mut *self.buffers[write_idx].get() }
    }

    // Publish write buffer (swap write and ready)
    pub fn publish(&self) {
        loop {
            let state = self.state.load(Ordering::Acquire);
            let write_idx = state & 0b11;
            let ready_idx = (state >> 2) & 0b11;
            let read_idx = (state >> 4) & 0b11;

            let new_state = ready_idx | (write_idx << 2) | (read_idx << 4);

            if self.state.compare_exchange_weak(
                state, new_state,
                Ordering::AcqRel, Ordering::Acquire
            ).is_ok() {
                break;
            }
        }
    }

    // Consumer side (Audio thread) - always gets latest published data
    pub fn read(&self) -> &T {
        // Atomically swap ready into read
        loop {
            let state = self.state.load(Ordering::Acquire);
            let write_idx = state & 0b11;
            let ready_idx = (state >> 2) & 0b11;
            let read_idx = (state >> 4) & 0b11;

            let new_state = write_idx | (read_idx << 2) | (ready_idx << 4);

            if self.state.compare_exchange_weak(
                state, new_state,
                Ordering::AcqRel, Ordering::Acquire
            ).is_ok() {
                break;
            }
        }

        let state = self.state.load(Ordering::Acquire);
        let read_idx = ((state >> 4) & 0b11) as usize;
        unsafe { &*self.buffers[read_idx].get() }
    }
}
```

### 1.5 Atomic Operations for Parameters

For simple scalar parameters, atomics are fastest.

```rust
use std::sync::atomic::{AtomicU64, Ordering};

pub struct AtomicParam {
    bits: AtomicU64,
}

impl AtomicParam {
    pub fn new(value: f64) -> Self {
        Self { bits: AtomicU64::new(value.to_bits()) }
    }

    #[inline(always)]
    pub fn get(&self) -> f64 {
        f64::from_bits(self.bits.load(Ordering::Relaxed))
    }

    #[inline(always)]
    pub fn set(&self, value: f64) {
        self.bits.store(value.to_bits(), Ordering::Relaxed);
    }

    // Smooth interpolation (call from audio thread)
    pub fn get_smoothed(&self, current: &mut f64, coeff: f64) -> f64 {
        let target = self.get();
        *current = *current + coeff * (target - *current);
        *current
    }
}
```

**Memory Ordering Reference:**
| Ordering | Use Case |
|----------|----------|
| `Relaxed` | Independent reads/writes (most params) |
| `Acquire` | Reading data written by another thread |
| `Release` | Writing data to be read by another thread |
| `AcqRel` | Read-modify-write operations (CAS) |
| `SeqCst` | Rarely needed, maximum ordering |

### 1.6 Wait-Free Algorithms

True wait-free means every operation completes in bounded time. Important for real-time guarantees.

```rust
// Wait-free atomic increment (bounded time)
counter.fetch_add(1, Ordering::Relaxed);

// Lock-free but NOT wait-free (unbounded CAS loops)
loop {
    let old = value.load(Ordering::Acquire);
    if value.compare_exchange(old, new, Ordering::AcqRel, Ordering::Acquire).is_ok() {
        break;  // Could loop indefinitely under contention
    }
}
```

**Wait-Free Patterns:**
1. Single-writer atomics (always wait-free)
2. Read-copy-update (RCU) for complex data
3. Hazard pointers for memory reclamation
4. Epoch-based reclamation (crossbeam-epoch)

---

## 2. Memory Management

### 2.1 Pre-allocation Strategies

Allocate everything at initialization, reuse during runtime.

```rust
pub struct AudioEngine {
    // Fixed-size scratch buffers (allocated once)
    scratch_l: Box<[f64; MAX_BUFFER_SIZE]>,
    scratch_r: Box<[f64; MAX_BUFFER_SIZE]>,
    fft_buffer: Box<[Complex<f64>; FFT_SIZE]>,

    // Object pool for dynamic needs
    buffer_pool: BufferPool,

    // Pre-allocated parameter update buffer
    param_buffer: Vec<ParamChange>,  // Vec::with_capacity(1024)
}

impl AudioEngine {
    pub fn new() -> Self {
        Self {
            scratch_l: Box::new([0.0; MAX_BUFFER_SIZE]),
            scratch_r: Box::new([0.0; MAX_BUFFER_SIZE]),
            fft_buffer: Box::new([Complex::default(); FFT_SIZE]),
            buffer_pool: BufferPool::new(16, MAX_BUFFER_SIZE),
            param_buffer: Vec::with_capacity(1024),
        }
    }
}
```

### 2.2 Memory Pools

Pool allocators for variable-size needs without heap calls.

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

    // O(1) acquire
    pub fn acquire(&mut self) -> Option<usize> {
        self.available.pop()
    }

    // O(1) release
    pub fn release(&mut self, index: usize) {
        self.buffers[index].fill(0.0);  // Clear for next use
        self.available.push(index);
    }

    pub fn get(&self, index: usize) -> &[f64] {
        &self.buffers[index]
    }

    pub fn get_mut(&mut self, index: usize) -> &mut [f64] {
        &mut self.buffers[index]
    }
}
```

### 2.3 Stack Allocation in Audio Thread

Use fixed-size arrays on stack, not heap.

```rust
// BAD: Heap allocation
fn process_bad(samples: &[f64]) -> Vec<f64> {
    let mut result = Vec::new();  // HEAP ALLOC
    for &s in samples {
        result.push(s * 2.0);     // POTENTIAL REALLOC
    }
    result
}

// GOOD: Stack allocation
fn process_good(samples: &[f64], output: &mut [f64]) {
    let mut temp: [f64; 256] = [0.0; 256];  // STACK

    for (i, &s) in samples.iter().enumerate().take(256) {
        temp[i] = s * 2.0;
    }

    output[..samples.len()].copy_from_slice(&temp[..samples.len()]);
}
```

### 2.4 Cache-Friendly Data Structures

Optimize for CPU cache (L1: 32KB, L2: 256KB, L3: 8MB typical).

```rust
// BAD: Array of Structs (AoS) - poor cache locality for SIMD
struct BiquadAoS {
    filters: Vec<Biquad>,  // Each Biquad has b0,b1,b2,a1,a2,z1,z2
}

// GOOD: Struct of Arrays (SoA) - perfect for SIMD
#[repr(C, align(64))]  // Cache-line aligned
pub struct BiquadSoA {
    b0: Vec<f64>,  // All b0 coefficients contiguous
    b1: Vec<f64>,
    b2: Vec<f64>,
    a1: Vec<f64>,
    a2: Vec<f64>,
    z1: Vec<f64>,
    z2: Vec<f64>,
}
```

### 2.5 Aligned Memory for SIMD

SIMD requires aligned memory for best performance.

```rust
// 64-byte alignment (cache line + AVX-512)
#[repr(C, align(64))]
pub struct AlignedBuffer {
    data: [f64; 1024],
}

// Or use aligned_vec crate
use aligned_vec::AVec;
let buffer: AVec<f64, aligned_vec::ConstAlign<64>> = AVec::new(64);

// Check alignment at runtime
fn process_aligned(buffer: &mut [f64]) {
    assert!(buffer.as_ptr() as usize % 64 == 0, "Buffer not 64-byte aligned");
    // ... SIMD processing
}
```

### 2.6 Denormal Prevention

Denormals (tiny floating-point numbers) cause massive CPU slowdowns.

```rust
// Method 1: Flush denormals to zero (FTZ) via CPU flags
pub fn enable_ftz() {
    #[cfg(target_arch = "x86_64")]
    unsafe {
        use std::arch::x86_64::*;
        _MM_SET_FLUSH_ZERO_MODE(_MM_FLUSH_ZERO_ON);
        _MM_SET_DENORMALS_ZERO_MODE(_MM_DENORMALS_ZERO_ON);
    }
}

// Method 2: Add tiny DC offset (works everywhere)
const DENORMAL_OFFSET: f64 = 1e-25;

fn prevent_denormal(x: f64) -> f64 {
    x + DENORMAL_OFFSET
}

// Method 3: In filter state updates (most critical place)
impl BiquadTDF2 {
    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        let output = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * output + self.z2;
        self.z2 = self.b2 * input - self.a2 * output;

        // Anti-denormal: flush tiny values
        const THRESHOLD: f64 = 1e-18;
        if self.z1.abs() < THRESHOLD { self.z1 = 0.0; }
        if self.z2.abs() < THRESHOLD { self.z2 = 0.0; }

        output
    }
}
```

---

## 3. Threading Models

### 3.1 Audio Thread Priority (Real-Time Scheduling)

Audio thread must have highest priority to avoid dropouts.

```rust
// macOS: Time Constraint Policy
#[cfg(target_os = "macos")]
fn set_realtime_priority_macos() {
    use std::mem;

    #[repr(C)]
    struct ThreadTimeConstraintPolicy {
        period: u32,
        computation: u32,
        constraint: u32,
        preemptible: i32,
    }

    extern "C" {
        fn pthread_self() -> usize;
        fn thread_policy_set(
            thread: usize,
            flavor: u32,
            policy_info: *const ThreadTimeConstraintPolicy,
            count: u32,
        ) -> i32;
    }

    unsafe {
        let policy = ThreadTimeConstraintPolicy {
            period: 48000,      // 1ms at 48kHz (samples)
            computation: 24000, // 0.5ms guaranteed
            constraint: 48000,  // Must complete within 1ms
            preemptible: 0,     // Don't preempt
        };

        let _ = thread_policy_set(
            pthread_self(),
            1, // THREAD_TIME_CONSTRAINT_POLICY
            &policy,
            mem::size_of::<ThreadTimeConstraintPolicy>() as u32 / 4,
        );
    }
}

// Linux: SCHED_FIFO
#[cfg(target_os = "linux")]
fn set_realtime_priority_linux() {
    use libc::{sched_param, sched_setscheduler, SCHED_FIFO};

    unsafe {
        let param = sched_param { sched_priority: 80 };
        let _ = sched_setscheduler(0, SCHED_FIFO, &param);
    }
}

// Windows: MMCSS (Multimedia Class Scheduler Service)
#[cfg(target_os = "windows")]
fn set_realtime_priority_windows() {
    // Use AvSetMmThreadCharacteristicsW with "Pro Audio" task
}
```

### 3.2 Worker Thread Pool for DSP

Heavy DSP (convolution, FFT) runs on worker threads, not audio thread.

```rust
use rayon::prelude::*;

// NEVER in audio thread - use for offline processing
fn parallel_analysis(tracks: &mut [Track]) {
    tracks.par_iter_mut().for_each(|track| {
        track.analyze_loudness();  // Heavy computation
    });
}

// For real-time: pre-compute on worker, swap atomically
struct ConvolutionEngine {
    ir_ready: AtomicBool,
    ir_buffer: TripleBuffer<Vec<f64>>,
}

impl ConvolutionEngine {
    fn load_ir_async(&self, path: &Path) {
        let ir_buffer = self.ir_buffer.clone();

        std::thread::spawn(move || {
            let ir = load_impulse_response(path);  // Slow I/O
            let processed = prepare_ir_partitions(&ir);  // Heavy DSP

            *ir_buffer.write() = processed;
            ir_buffer.publish();
            ir_ready.store(true, Ordering::Release);
        });
    }

    fn process(&mut self, input: &[f64], output: &mut [f64]) {
        if self.ir_ready.load(Ordering::Acquire) {
            let ir = self.ir_buffer.read();
            convolve_partitioned(input, ir, output);
        }
    }
}
```

### 3.3 GUI Thread Separation

GUI never touches audio data directly. Always via lock-free channels.

```
┌─────────────┐     Lock-Free Queue    ┌─────────────┐
│  GUI Thread │ ───────────────────────▶ │Audio Thread │
│  (60 fps)   │ ◀─────────────────────── │(48000/128)  │
└─────────────┘     Meter/Vis Data      └─────────────┘
        │
        │ Main Event Loop
        ▼
┌─────────────┐
│ Render Loop │
│  (vsync)    │
└─────────────┘
```

```rust
// Meter data from audio to GUI
pub struct MeterData {
    pub peak_l: f32,
    pub peak_r: f32,
    pub rms_l: f32,
    pub rms_r: f32,
    pub lufs: f32,
}

// Audio thread sends (non-blocking, drop if full)
fn audio_callback(buffer: &[f32], meter_tx: &Producer<MeterData>) {
    let meters = calculate_meters(buffer);
    let _ = meter_tx.push(meters);  // Ignore if full
}

// GUI thread receives (throttled to 30fps for meters)
fn gui_update(meter_rx: &mut Consumer<MeterData>, last_update: &mut Instant) {
    if last_update.elapsed() < Duration::from_millis(33) {
        return;  // Throttle to 30fps
    }

    // Drain all pending meter data, use latest
    let mut latest = None;
    while let Ok(data) = meter_rx.pop() {
        latest = Some(data);
    }

    if let Some(meters) = latest {
        update_meter_display(meters);
        *last_update = Instant::now();
    }
}
```

### 3.4 Message Passing vs Shared State

| Approach | Use Case | Pros | Cons |
|----------|----------|------|------|
| Message Passing (Queue) | Parameter changes, commands | Clear ownership, no races | Latency (1 buffer) |
| Shared State (Atomic) | Simple scalars (gain, pan) | Zero latency | Limited to primitives |
| Triple Buffer | Complex state (presets) | Always fresh data | Memory overhead |

**Rule of thumb:** Use atomics for parameters that need instant response (fader moves), queues for everything else.

---

## 4. SIMD Optimization

### 4.1 Runtime Dispatch Pattern

Detect CPU features at runtime, dispatch to best implementation.

```rust
#[cfg(target_arch = "x86_64")]
pub fn process_block(samples: &mut [f64]) {
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
pub fn process_block(samples: &mut [f64]) {
    unsafe { process_neon(samples) }  // NEON always available
}
```

### 4.2 SIMD Vector Widths

| Instruction Set | Register Size | f64 per Register | f32 per Register |
|-----------------|---------------|------------------|------------------|
| SSE4.2 | 128-bit | 2 | 4 |
| AVX2 | 256-bit | 4 | 8 |
| AVX-512 | 512-bit | 8 | 16 |
| NEON | 128-bit | 2 | 4 |

### 4.3 AVX2 Gain Processing

```rust
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2")]
unsafe fn apply_gain_avx2(samples: &mut [f64], gain: f64) {
    use std::arch::x86_64::*;

    let gain_vec = _mm256_set1_pd(gain);
    let chunks = samples.len() / 4;

    for i in 0..chunks {
        let ptr = samples.as_mut_ptr().add(i * 4);
        let data = _mm256_loadu_pd(ptr);
        let result = _mm256_mul_pd(data, gain_vec);
        _mm256_storeu_pd(ptr, result);
    }

    // Handle remainder (always include!)
    for i in (chunks * 4)..samples.len() {
        samples[i] *= gain;
    }
}
```

### 4.4 AVX-512 Biquad Filter

```rust
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx512f")]
unsafe fn process_biquad_avx512(
    samples: &mut [f64],
    coeffs: &BiquadCoeffs,
    z1: &mut f64,
    z2: &mut f64,
) {
    use std::arch::x86_64::*;

    let b0 = _mm512_set1_pd(coeffs.b0);
    let b1 = _mm512_set1_pd(coeffs.b1);
    let b2 = _mm512_set1_pd(coeffs.b2);
    let a1 = _mm512_set1_pd(coeffs.a1);
    let a2 = _mm512_set1_pd(coeffs.a2);

    let chunks = samples.len() / 8;

    for i in 0..chunks {
        let ptr = samples.as_mut_ptr().add(i * 8);
        let input = _mm512_loadu_pd(ptr);

        // TDF-II: output = b0*input + z1
        let mut z1_vec = _mm512_set1_pd(*z1);
        let mut z2_vec = _mm512_set1_pd(*z2);

        let output = _mm512_fmadd_pd(b0, input, z1_vec);

        // z1 = b1*input - a1*output + z2
        z1_vec = _mm512_fmadd_pd(b1, input, z2_vec);
        z1_vec = _mm512_fnmadd_pd(a1, output, z1_vec);

        // z2 = b2*input - a2*output
        z2_vec = _mm512_mul_pd(b2, input);
        z2_vec = _mm512_fnmadd_pd(a2, output, z2_vec);

        _mm512_storeu_pd(ptr, output);

        // Extract state from last lane for next iteration
        *z1 = _mm512_reduce_add_pd(z1_vec) / 8.0;  // Simplified
        *z2 = _mm512_reduce_add_pd(z2_vec) / 8.0;
    }

    // Scalar remainder
    for i in (chunks * 8)..samples.len() {
        let input = samples[i];
        let output = coeffs.b0 * input + *z1;
        *z1 = coeffs.b1 * input - coeffs.a1 * output + *z2;
        *z2 = coeffs.b2 * input - coeffs.a2 * output;
        samples[i] = output;
    }
}
```

### 4.5 SIMD Biquad Bank (Parallel Filters)

Process multiple biquads simultaneously (useful for multi-band EQ).

```rust
use std::simd::{f64x4, f64x8};

#[derive(Debug, Clone)]
pub struct BiquadBank4 {
    pub b0: f64x4, pub b1: f64x4, pub b2: f64x4,
    pub a1: f64x4, pub a2: f64x4,
    pub z1: f64x4, pub z2: f64x4,
}

impl BiquadBank4 {
    // Process 4 independent biquads with same input
    #[inline(always)]
    pub fn process(&mut self, input: f64x4) -> f64x4 {
        let output = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * output + self.z2;
        self.z2 = self.b2 * input - self.a2 * output;
        output
    }
}

// Process 8 biquads in parallel (AVX-512)
pub struct BiquadBank8 {
    pub b0: f64x8, pub b1: f64x8, pub b2: f64x8,
    pub a1: f64x8, pub a2: f64x8,
    pub z1: f64x8, pub z2: f64x8,
}
```

### 4.6 Data Alignment Requirements

```rust
// Aligned load/store (faster, but requires alignment)
let data = _mm256_load_pd(ptr);   // ptr must be 32-byte aligned
_mm256_store_pd(ptr, data);

// Unaligned load/store (works everywhere, slightly slower)
let data = _mm256_loadu_pd(ptr);  // ptr can be any alignment
_mm256_storeu_pd(ptr, data);

// Check alignment
fn is_aligned<T>(ptr: *const T, alignment: usize) -> bool {
    ptr as usize % alignment == 0
}
```

### 4.7 Auto-Vectorization Hints

Help the compiler auto-vectorize without manual intrinsics.

```rust
// Tell compiler this is vectorizable
#[inline(always)]
fn process_vectorized(input: &[f64], output: &mut [f64], gain: f64) {
    // Bounds check elimination
    assert_eq!(input.len(), output.len());

    // Process in chunks for better vectorization
    for (i, o) in input.iter().zip(output.iter_mut()) {
        *o = *i * gain;
    }
}

// Use iterators (often vectorizes better)
output.iter_mut()
    .zip(input.iter())
    .for_each(|(o, i)| *o = *i * gain);
```

### 4.8 Batch Processing Patterns

Process multiple samples at once for SIMD efficiency.

```rust
pub struct BatchProcessor {
    block_size: usize,
    channels: usize,
    interleaved: Vec<f64>,  // Pre-allocated
}

impl BatchProcessor {
    // Process in optimal block sizes (multiple of vector width)
    pub fn process<F>(&mut self, input: &[f64], output: &mut [f64], mut f: F)
    where F: FnMut(&mut [f64])
    {
        let block = 256;  // 64 samples * 4 channels = 256, divisible by 8

        for (in_chunk, out_chunk) in input.chunks(block).zip(output.chunks_mut(block)) {
            out_chunk.copy_from_slice(in_chunk);
            f(out_chunk);
        }
    }
}
```

---

## 5. Latency Management

### 5.1 Plugin Delay Compensation (PDC)

When plugins add latency, compensate parallel paths to maintain phase coherence.

```
Input ──┬──▶ [Plugin A: 0 samples] ──┬──▶ Sum ──▶ Output
        │                            │
        └──▶ [Plugin B: 256 samples] ┴──[Delay: 256]──┘
```

```rust
pub struct PdcManager {
    paths: HashMap<u32, PathLatency>,
    max_latency: AtomicU32,
}

pub struct PathLatency {
    pub id: u32,
    pub processors: Vec<ProcessorLatency>,
    pub total_samples: u32,
    pub compensation_delay: u32,  // Added delay to match longest path
}

impl PdcManager {
    pub fn recalculate_compensation(&mut self) {
        // Find maximum latency across all paths
        let max = self.paths.values()
            .map(|p| p.total_samples)
            .max()
            .unwrap_or(0);

        self.max_latency.store(max, Ordering::Release);

        // Set compensation for shorter paths
        for path in self.paths.values_mut() {
            path.compensation_delay = max.saturating_sub(path.total_samples);
        }
    }
}
```

### 5.2 Look-ahead Buffers

Limiters and compressors need look-ahead for transparent operation.

```rust
pub struct LookaheadBuffer {
    buffer: Vec<f64>,
    write_pos: usize,
    delay_samples: usize,
}

impl LookaheadBuffer {
    pub fn new(max_delay: usize) -> Self {
        Self {
            buffer: vec![0.0; max_delay],
            write_pos: 0,
            delay_samples: 0,
        }
    }

    pub fn set_delay(&mut self, samples: usize) {
        self.delay_samples = samples.min(self.buffer.len());
    }

    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        if self.delay_samples == 0 {
            return input;
        }

        let cap = self.buffer.len();
        let read_pos = (self.write_pos + cap - self.delay_samples) % cap;
        let output = self.buffer[read_pos];

        self.buffer[self.write_pos] = input;
        self.write_pos = (self.write_pos + 1) % cap;

        output
    }
}
```

### 5.3 Sample-Accurate Automation

Automation changes must happen at exact sample positions, not buffer boundaries.

```rust
pub struct AutomationLane {
    pub points: Vec<AutomationPoint>,  // Sorted by position
}

pub struct AutomationPoint {
    pub position: u64,      // Sample position
    pub value: f64,
    pub curve: CurveType,
}

impl AutomationLane {
    // Get interpolated value at exact sample position
    pub fn value_at(&self, position: u64) -> Option<f64> {
        if self.points.is_empty() { return None; }

        // Binary search for surrounding points
        let idx = self.points.binary_search_by(|p| p.position.cmp(&position))
            .unwrap_or_else(|i| i);

        if idx == 0 {
            return Some(self.points[0].value);
        }
        if idx >= self.points.len() {
            return Some(self.points.last().unwrap().value);
        }

        let p1 = &self.points[idx - 1];
        let p2 = &self.points[idx];

        // Interpolate based on curve type
        let t = (position - p1.position) as f64 / (p2.position - p1.position) as f64;
        Some(interpolate(p1.value, p2.value, t, p1.curve))
    }
}

fn interpolate(v1: f64, v2: f64, t: f64, curve: CurveType) -> f64 {
    match curve {
        CurveType::Linear => v1 + (v2 - v1) * t,
        CurveType::Step => v1,
        CurveType::Exponential => v1 + (v2 - v1) * t * t,
        CurveType::SCurve => {
            let t_s = t * t * (3.0 - 2.0 * t);  // Smoothstep
            v1 + (v2 - v1) * t_s
        }
    }
}
```

### 5.4 Latency Reporting

Report total plugin latency for host PDC.

```rust
pub trait Processor {
    fn process(&mut self, input: &[f64], output: &mut [f64]);

    fn latency(&self) -> usize {
        0  // Override for processors with inherent latency
    }
}

// Linear phase EQ: FIR length / 2
impl Processor for LinearPhaseEq {
    fn latency(&self) -> usize {
        self.fir_length / 2  // e.g., 4096 / 2 = 2048 samples
    }
}

// Lookahead limiter: lookahead time
impl Processor for LookaheadLimiter {
    fn latency(&self) -> usize {
        self.lookahead_samples  // e.g., 128 samples
    }
}
```

---

## 6. Quick Reference

### Anti-Patterns (NEVER DO)

| Pattern | Problem | Solution |
|---------|---------|----------|
| `mutex.lock()` in audio | Can block indefinitely | Atomics, lock-free queues |
| `Vec::push()` in audio | Heap allocation | Pre-allocate, fixed arrays |
| `println!()` in audio | System call | Lock-free logging |
| `file.read()` in audio | Blocking I/O | Async load on worker thread |
| `.unwrap()` in audio | Can panic | `.unwrap_or()`, error codes |
| `log10()/pow()` per sample | Expensive | Lookup tables |
| Branch per sample | Pipeline stalls | Branchless SIMD |

### Performance Targets

| Metric | Target | Critical Limit |
|--------|--------|----------------|
| Audio callback | < 50% buffer time | < 90% |
| DSP load (48kHz stereo) | < 20% CPU | < 50% |
| Latency (128 samples) | < 2.67ms | < 5ms |
| Memory per track | < 50MB | < 200MB |
| Startup time | < 2s | < 5s |

### Profiling Commands

```bash
# CPU profiling
cargo flamegraph --release

# Memory profiling (macOS)
instruments -t "Allocations" ./target/release/app

# Audio callback timing
cargo test --release -- --nocapture audio_latency_test

# SIMD verification
objdump -d target/release/app | grep -E "(vmov|vadd|vmul)"
```

### Benchmarking Template

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_biquad(c: &mut Criterion) {
    let mut filter = BiquadTDF2::bell(1000.0, 1.0, 6.0, 48000.0);
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

---

## References

- Ross Bencina: "Real-time Audio Programming 101" (ADC 2017)
- Fabian Renn-Giles: "Real-time 101" (ADC 2019)
- Jeff Preshing: "An Introduction to Lock-Free Programming"
- Intel Intrinsics Guide: https://www.intel.com/content/www/us/en/docs/intrinsics-guide/
- Rust SIMD: https://doc.rust-lang.org/std/simd/

---

**Document Version:** 1.0
**Last Updated:** 2026-01-10
**Author:** Engine Architecture Team

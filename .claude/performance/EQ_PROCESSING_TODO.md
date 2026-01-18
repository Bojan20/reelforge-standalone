# EQ Signal Processing Implementation TODO

**Status:** NOT IMPLEMENTED — Audio currently bypasses EQ
**Priority:** HIGH — Core feature missing
**Complexity:** Medium (2-3h implementation)

---

## Current State

**File:** `crates/rf-audio/src/engine.rs:371-391`

```rust
// For now, passthrough (processor will be called in future)
// In production, we'd call processor.process() here
// but we can't easily share the Mutex across callback boundary

// Generate test tone when playing (440Hz sine)
if state == TransportState::Playing {
    let sample_rate = 48000.0;
    let freq = 440.0;
    let pos = transport.samples();

    for i in 0..frames {
        let t = (pos + i as u64) as f64 / sample_rate;
        let sample = (2.0 * std::f64::consts::PI * freq * t).sin() * 0.3;
        left_buf[i] = sample;  // ❌ NO EQ PROCESSING
        right_buf[i] = sample;
    }
}
```

**Problem:** Test tone je generisan ali **nikad ne prolazi kroz EQ filtere**.

---

## Why EQ Is Not Called

**AudioEngine Structure** (`engine.rs:275-288`):
```rust
pub struct AudioEngine {
    processor: Mutex<Box<dyn AudioProcessor>>,  // ❌ Locked
    // ...
}
```

**Audio Callback** (`engine.rs:350`):
```rust
let callback = Box::new(move |input: &[Sample], output: &mut [Sample]| {
    // ❌ Can't access processor because:
    // 1. It's behind Mutex (FORBIDDEN in audio thread)
    // 2. Not moved into closure
    // 3. No lock-free communication setup
});
```

---

## Solution Architecture

### Option 1: Move EQ Instance Into Callback (BEST)

**Pros:**
- Zero locks in audio thread ✅
- Direct EQ access ✅
- Maximum performance ✅

**Cons:**
- Can't replace EQ instance after callback created
- Parameter updates need lock-free channel

**Implementation:**

```rust
use rtrb::RingBuffer;
use rf_dsp::Equalizer;

pub fn start_stream(&mut self) -> AudioResult<()> {
    let settings = self.settings.read();

    // Create EQ instance (move ownership to audio thread)
    let mut eq = Equalizer::new(settings.sample_rate.as_f64());

    // Enable default band (1kHz +6dB for testing)
    eq.bands[0].enabled = true;
    eq.bands[0].frequency = 1000.0;
    eq.bands[0].gain_db = 6.0;
    eq.bands[0].filter_type = EqFilterType::Bell;
    eq.bands[0].q = 1.0;

    // Lock-free parameter channel
    let (param_tx, mut param_rx) = RingBuffer::<EqParamChange>::new(1024);

    let callback = Box::new(move |input: &[Sample], output: &mut [Sample]| {
        // 1. Process parameter updates (non-blocking)
        while let Ok(change) = param_rx.pop() {
            apply_eq_param(&mut eq, change);
        }

        // 2. Process audio through EQ
        for i in 0..frames {
            let (out_l, out_r) = eq.process_sample(left_buf[i], right_buf[i]);
            left_buf[i] = out_l;
            right_buf[i] = out_r;
        }

        // 3. Interleave to output
        // ...
    });

    // Store param_tx for FFI parameter updates
    self.eq_param_tx = Some(param_tx);
}

// FFI method
pub fn set_eq_band(&self, band_id: usize, freq: f64, gain_db: f64, q: f64) {
    if let Some(tx) = &self.eq_param_tx {
        let change = EqParamChange { band_id, freq, gain_db, q };
        let _ = tx.push(change); // Non-blocking
    }
}
```

---

### Option 2: Arc + Lock-Free State (Alternative)

**Pros:**
- Can swap EQ instances
- Shared ownership

**Cons:**
- More complex
- Atomic access overhead

**Structure:**
```rust
pub struct AudioEngine {
    eq_state: Arc<LockFreeEqState>,  // AtomicU64 for parameters
    // ...
}

struct LockFreeEqState {
    band_enabled: [AtomicBool; 64],
    band_freq: [AtomicU64; 64],     // f64::to_bits
    band_gain: [AtomicU64; 64],
    band_q: [AtomicU64; 64],
    needs_update: [AtomicBool; 64],
}
```

---

## Implementation Steps

### Phase 1: Basic EQ Processing (1h)

1. ✅ Move `Equalizer::new()` into callback closure
2. ✅ Replace test tone loop with EQ processing loop
3. ✅ Enable 1 test band (1kHz +6dB)
4. ✅ Test: Audio should have +6dB boost at 1kHz

**Files:**
- `crates/rf-audio/src/engine.rs:350-391`

**Code:**
```rust
// Inside start_stream()
let mut eq = Equalizer::new(sr);
eq.bands[0].enabled = true;
eq.bands[0].frequency = 1000.0;
eq.bands[0].gain_db = 6.0;
eq.bands[0].needs_update = true;

let callback = move || {
    for i in 0..frames {
        // Generate test tone
        let sample = ...;

        // Process through EQ
        let (out_l, out_r) = eq.process_sample(sample, sample);
        left_buf[i] = out_l;
        right_buf[i] = out_r;
    }
};
```

---

### Phase 2: Lock-Free Parameter Updates (1h)

5. ✅ Add `rtrb` ring buffer for parameter changes
6. ✅ Create `EqParamChange` struct
7. ✅ Store `Producer` in `AudioEngine`
8. ✅ Consume parameters in callback (non-blocking)

**Files:**
- `crates/rf-audio/src/engine.rs` (add field + FFI methods)
- `crates/rf-bridge/src/lib.rs` (expose FFI: `set_eq_band`)

---

### Phase 3: Flutter Integration (1h)

9. ✅ Add FFI bindings in `engine_api.dart`
10. ✅ Wire up EQ editor to call FFI
11. ✅ Test: Moving EQ frequency should change sound

**Files:**
- `flutter_ui/lib/src/rust/engine_api.dart`
- `flutter_ui/lib/widgets/editors/eq_editor.dart`

---

## Testing Checklist

- [ ] Test tone (440Hz) + 1kHz band enabled → Hear boost
- [ ] Sweep EQ frequency 100Hz-10kHz → Hear filter move
- [ ] Change gain -12dB to +12dB → Hear volume change
- [ ] Disable band → Hear flat response
- [ ] Enable multiple bands → Hear cascaded filtering
- [ ] High Q (10.0) → Hear narrow peak
- [ ] Low Q (0.5) → Hear wide shelf

---

## Performance Considerations

**Per-Sample Cost:**
- 1 enabled band: ~50 CPU cycles (1 biquad)
- 8 enabled bands: ~400 CPU cycles
- 64 enabled bands: ~3200 CPU cycles

**Target:** < 20% CPU @ 44.1kHz stereo with 8 bands

**Optimization Opportunities:**
1. SIMD biquad processing (AVX-512: 8 samples/cycle)
2. Skip disabled bands (early exit)
3. Pre-compute coefficient updates outside audio thread
4. Dirty-bit caching (skip update if params unchanged)

---

## Related Files

**DSP:**
- `crates/rf-dsp/src/eq.rs` — Equalizer implementation
- `crates/rf-dsp/src/biquad.rs` — Biquad filters

**Audio Engine:**
- `crates/rf-audio/src/engine.rs` — Audio callback

**Bridge:**
- `crates/rf-bridge/src/lib.rs` — FFI bindings

**Flutter:**
- `flutter_ui/lib/widgets/editors/eq_editor.dart` — UI
- `flutter_ui/lib/src/rust/engine_api.dart` — Dart FFI

---

**Priority:** Implementiraj Fazu 1 (basic EQ processing) PRVO — omogući da audio prolazi kroz EQ filtere.

**Estimated Time:** 3 hours total (1h + 1h + 1h)

**Status:** Ready to implement (all analysis complete)

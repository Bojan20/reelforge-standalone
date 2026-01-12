# FluxForge Studio Insert Chain Architecture

## IMPLEMENTED SOLUTION (2026-01-11)

### Root Causes Found

1. **`validate_param_index` limit was 15** - EQ uses `band * 11` params, so band 2 = param 22 was rejected
2. **`rx.slots()` wrong API** - Returns writable slots, not readable items. Fixed to `rx.is_empty()`
3. **Ring buffer tx/rx were separate** - Created two independent buffers instead of one split pair

### Key Fixes Applied

**File: `crates/rf-engine/src/ffi.rs`**
```rust
// BEFORE: Max param was 15 (broken for EQ)
fn validate_param_index(param_index: u32) -> Option<u32> {
    if param_index > 15 { None } else { Some(param_index) }
}

// AFTER: Max param is 1024 (64 bands * 11 params = 704)
fn validate_param_index(param_index: u32) -> Option<u32> {
    if param_index > 1024 { None } else { Some(param_index) }
}
```

**File: `crates/rf-engine/src/playback.rs`**
```rust
// Ring buffer initialization - MUST be single buffer split into tx/rx
let (insert_param_tx, insert_param_rx) = rtrb::RingBuffer::<InsertParamChange>::new(4096);

// BEFORE: rx.slots() == 0 (WRONG - slots() is for writing)
// AFTER: rx.is_empty() (CORRECT - checks if readable items exist)
if rx.is_empty() {
    return; // Nothing to consume
}
```

**File: `crates/rf-engine/src/insert_chain.rs`**
```rust
// Added InsertParamChange struct for lock-free communication
#[derive(Clone, Copy, Debug)]
pub struct InsertParamChange {
    pub track_id: u64,
    pub slot_index: u8,
    pub param_index: u16,
    pub value: f64,
}
```

### Signal Flow (Working)

```
Flutter UI (onBandChange)
    │
    ▼
NativeFFI.insertSetParam(trackId=1, slot=0, param=22, value=1000.0)
    │
    ▼
FFI: insert_set_param() → validate_param_index(22) ✓ (now allows up to 1024)
    │
    ▼
PlaybackEngine::set_track_insert_param()
    │
    ▼
insert_param_tx.push(InsertParamChange) → Ring Buffer (4096 slots)
    │
    ▼
Audio Thread: process() → consume_insert_param_changes()
    │
    ▼
insert_param_rx.pop() → chain.set_slot_param()
    │
    ▼
ProEqWrapper::set_param(22, 1000.0) → band 2 freq = 1000 Hz
    │
    ▼
ProEq::process_block() → Audio affected!
```

### Verification

```
flutter: [EQ] insertSetParam(track=1, slot=0, param=22, value=1749.45) -> result=1
```

`result=1` confirms FFI succeeded. Previously was `result=0` due to param validation failure.

---

## Problem Analysis

### Current Implementation Issues

1. **RwLock Contention** (`playback.rs:689`)
   - `insert_chains: RwLock<HashMap<u64, InsertChain>>`
   - UI thread calls `write()` for parameter changes → blocks
   - Audio thread calls `try_write()` → returns None when contended
   - **Result**: Inserts silently skipped during parameter updates

2. **Parameter Path** (UI → Audio)
   ```
   Flutter UI → FFI → set_track_insert_param() → RwLock::write() → chain.set_slot_param()
                                                    ↑
                                              BLOCKS HERE
   ```

3. **Audio Callback** (`playback.rs:1710`)
   ```rust
   if let Some(mut chains) = self.insert_chains.try_write() {  // Often fails!
       if let Some(chain) = chains.get_mut(&track.id.0) {
           chain.process_pre_fader(track_l, track_r);
       }
   }
   ```

---

## Proposed Architecture

### Lock-Free Insert Chain Design

```
┌─────────────────────────────────────────────────────────────────┐
│                         UI THREAD                                │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Flutter EQ Widget                                          │   │
│  │   └── onFrequencyChanged(bandIndex, freq)                 │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                    │
│                              ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ FFI: eq_set_band_frequency(trackId, bandIndex, freq)      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                    │
└──────────────────────────────┼────────────────────────────────────┘
                               │
                               ▼ NON-BLOCKING PUSH
┌──────────────────────────────────────────────────────────────────┐
│                    LOCK-FREE RING BUFFER                          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ rtrb::RingBuffer<ParamChange>                              │  │
│  │   [{ track: 1, slot: 0, param: 0, value: 1000.0 }, ...]    │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼ NON-BLOCKING POP (per block)
┌──────────────────────────────────────────────────────────────────┐
│                       AUDIO THREAD                                │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ fn process_block() {                                        │  │
│  │     // 1. Consume ALL pending param changes (lock-free)     │  │
│  │     while let Ok(change) = param_rx.pop() {                 │  │
│  │         apply_param_change(change);                         │  │
│  │     }                                                        │  │
│  │                                                              │  │
│  │     // 2. Process audio through insert chains               │  │
│  │     for track in tracks {                                   │  │
│  │         chain.process_pre_fader(left, right);  // NEVER BLOCKED │
│  │         // ... fader ...                                     │  │
│  │         chain.process_post_fader(left, right);              │  │
│  │     }                                                        │  │
│  │ }                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Data Structures

### 1. Parameter Change Message

```rust
/// Lock-free parameter change message
#[derive(Clone, Copy)]
pub struct InsertParamChange {
    /// Target track ID (0 = master)
    pub track_id: u64,
    /// Insert slot index (0-9)
    pub slot_index: u8,
    /// Parameter index within processor
    pub param_index: u16,
    /// New parameter value
    pub value: f64,
    /// Sample offset for sample-accurate automation (optional)
    pub sample_offset: u32,
}
```

### 2. InsertChain with Atomic Parameters

```rust
/// Insert chain owned entirely by audio thread
pub struct InsertChain {
    pre_slots: [InsertSlot; 5],
    post_slots: [InsertSlot; 5],

    /// Consumed by audio thread from ring buffer
    /// Applied at start of each process block
    pending_changes: Vec<InsertParamChange>,  // Pre-allocated, reused
}

impl InsertChain {
    /// Called at START of each audio block (before any processing)
    pub fn apply_pending_params(&mut self, rx: &mut Consumer<InsertParamChange>) {
        // Drain all pending changes (non-blocking)
        while let Ok(change) = rx.pop() {
            if let Some(slot) = self.slot_mut(change.slot_index as usize) {
                slot.set_processor_param(change.param_index as usize, change.value);
            }
        }
    }
}
```

### 3. Per-Processor Atomic Parameters (EQ Example)

```rust
/// ProEQ with lock-free parameter access
pub struct ProEqWrapper {
    eq: ProEq,

    /// Atomic parameter storage (UI writes, audio reads)
    /// Layout: [band0_freq, band0_gain, band0_q, band0_enabled, band0_shape, ...]
    params: Box<[AtomicU64; MAX_BANDS * PARAMS_PER_BAND]>,

    /// Flag: true when params changed, audio thread clears after reading
    needs_update: AtomicBool,
}

impl ProEqWrapper {
    /// UI thread: set parameter (lock-free)
    pub fn set_param(&self, index: usize, value: f64) {
        self.params[index].store(value.to_bits(), Ordering::Release);
        self.needs_update.store(true, Ordering::Release);
    }

    /// Audio thread: apply pending changes before processing
    fn sync_params(&mut self) {
        if self.needs_update.swap(false, Ordering::Acquire) {
            // Read atomic params and update EQ coefficients
            for band in 0..self.eq.active_bands() {
                let base = band * PARAMS_PER_BAND;
                let freq = f64::from_bits(self.params[base].load(Ordering::Acquire));
                let gain = f64::from_bits(self.params[base + 1].load(Ordering::Acquire));
                let q = f64::from_bits(self.params[base + 2].load(Ordering::Acquire));

                self.eq.set_band_frequency(band, freq);
                self.eq.set_band_gain(band, gain);
                self.eq.set_band_q(band, q);
            }
        }
    }
}

impl InsertProcessor for ProEqWrapper {
    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.sync_params();  // Apply pending changes first
        self.eq.process_stereo(left, right);
    }
}
```

---

## Implementation Plan

### Phase 1: Lock-Free Parameter Queue

**Files to modify:**
- `crates/rf-engine/src/playback.rs`
- `crates/rf-engine/src/insert_chain.rs`

**Changes:**
1. Add `rtrb` ring buffer for param changes
2. Replace `RwLock<HashMap<u64, InsertChain>>` with owned `HashMap`
3. Audio thread consumes params at block start
4. Remove `try_write()` - use direct mutable access

```rust
// In PlaybackEngine
pub struct PlaybackEngine {
    // REMOVE: insert_chains: RwLock<HashMap<u64, InsertChain>>,

    // NEW: Owned by audio thread (no lock)
    insert_chains: UnsafeCell<HashMap<u64, InsertChain>>,

    // NEW: Lock-free param queue
    param_tx: Producer<InsertParamChange>,
    param_rx: Consumer<InsertParamChange>,
}
```

### Phase 2: Atomic Parameters in Processors

**Files to modify:**
- `crates/rf-engine/src/dsp_wrappers.rs`
- `crates/rf-dsp/src/eq_pro.rs`

**Changes:**
1. Add `AtomicU64` array for parameters
2. Add `needs_update: AtomicBool` flag
3. `set_param()` writes to atomics (lock-free)
4. `process_stereo()` syncs params before processing

### Phase 3: Coefficient Smoothing

**Optional but recommended:**
- Smooth parameter changes to avoid zipper noise
- Per-sample interpolation for automation
- Crossfade on bypass toggle

---

## Key Principles

### Audio Thread Rules (MUST FOLLOW)

```rust
// IN AUDIO CALLBACK:

// ✅ ALLOWED
atomic.load(Ordering::Acquire)
atomic.store(value, Ordering::Release)
ring_buffer.pop()  // non-blocking
pre_allocated_vec.push()  // if capacity exists
direct_field_access

// ❌ FORBIDDEN
mutex.lock()
rwlock.read() / rwlock.write()
rwlock.try_read() / rwlock.try_write()  // Still causes skipping!
Vec::push() when at capacity (allocates)
Box::new(), String::new()
println!, log::info!
file I/O, network
panic!, unwrap() on None/Err
```

### Lock-Free Communication Pattern

```
UI Thread                    Audio Thread
    │                            │
    │  param_tx.push(change)     │
    │  ─────────────────────►    │
    │     (non-blocking)         │
    │                            │ param_rx.pop()
    │                            │ ─────────────►
    │                            │   (per block)
    │                            │
    │                            │ apply to processor
    │                            │ ─────────────►
    │                            │
    │                            │ process audio
    │                            │ ─────────────►
```

---

## Testing Strategy

### 1. Unit Tests
```rust
#[test]
fn test_lock_free_param_update() {
    let (tx, rx) = rtrb::RingBuffer::new(1024);
    let mut chain = InsertChain::new(48000.0);

    // Simulate UI update
    tx.push(InsertParamChange {
        track_id: 1,
        slot_index: 0,
        param_index: 0,
        value: 1000.0,
        sample_offset: 0,
    }).unwrap();

    // Simulate audio block
    chain.apply_pending_params(&mut rx);

    // Verify param applied
    assert_eq!(chain.get_slot_param(0, 0), 1000.0);
}
```

### 2. Integration Test
- Start audio playback
- Rapidly change EQ frequency from UI
- Verify:
  - No audio dropouts
  - EQ affects signal continuously
  - No glitches/clicks

### 3. Stress Test
```rust
#[test]
fn stress_test_param_flood() {
    // Send 10000 param changes while audio is processing
    // Verify all changes eventually applied
    // Verify no memory leaks
}
```

---

## Migration Path

### Step 1: Add Ring Buffer (Non-Breaking)
- Add `param_tx`/`param_rx` alongside existing `RwLock`
- Route new params through queue
- Keep fallback to `RwLock` for compatibility

### Step 2: Move InsertChain to Audio Thread Ownership
- Remove `RwLock` wrapper
- Use `UnsafeCell` with proper Send/Sync bounds
- Audio thread has exclusive mutable access

### Step 3: Update Processors to Use Atomics
- Add atomic params to `ProEqWrapper`, etc.
- `set_param()` writes to atomics
- `process_stereo()` syncs before processing

### Step 4: Remove Legacy Lock Path
- Delete `try_write()` calls
- Verify with stress tests

---

## References

- [rtrb - Real-Time Ring Buffer](https://github.com/mgeier/rtrb)
- [Lock-Free Audio Processing](https://timur.audio/using-locks-in-real-time-audio-processing-safely)
- [VST3 Parameter Handling](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical+Documentation/Parameters+Automation/Index.html)
- [JUCE AudioProcessorValueTreeState](https://docs.juce.com/master/classAudioProcessorValueTreeState.html)

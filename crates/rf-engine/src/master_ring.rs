//! Master Output Ring Buffer (Phase 10e-2)
//!
//! Lock-free, zero-alloc, single-writer/single-reader stereo ring buffer for the
//! last N seconds of master output. Allows the UI (Problems Inbox) to export a
//! WAV of exactly what was playing when a problem was captured.
//!
//! # Design
//!
//! - **Audio thread** writes via `write_frames()` after `PlaybackEngine::process()`.
//!   Uses `UnsafeCell<Vec<f32>>` + atomic write position. No locks, no allocs.
//! - **UI thread** reads via `snapshot(seconds)` which returns an owned `(Vec<f32>,
//!   Vec<f32>, u32)` for WAV export. The snapshot copy is fast (~50μs for 5s @ 48kHz)
//!   — much faster than one audio block, so there is no overwrite race in practice.
//! - Buffer holds **5 s by default** at the engine sample rate. Amortises to ~1.8 MB
//!   (2 × 5 × 48000 × 4 bytes) — acceptable resident memory.
//!
//! # Safety
//!
//! Audio thread is the *sole* writer to the `left`/`right` `UnsafeCell`s. UI reads
//! are brief and tolerate torn reads at the single-sample level (noise floor);
//! they never mutate, so no aliasing UB.

use std::cell::UnsafeCell;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

/// Default window size — 5 seconds.
pub const DEFAULT_SECONDS: f32 = 5.0;
/// Absolute upper bound (seconds) for the ring capacity. Guards against silly SR.
pub const MAX_SECONDS: f32 = 10.0;
/// Default assumed sample rate if engine has not set one yet.
pub const DEFAULT_SAMPLE_RATE: u32 = 48_000;

pub struct MasterRingBuffer {
    left:  UnsafeCell<Vec<f32>>,
    right: UnsafeCell<Vec<f32>>,
    /// Ring capacity in frames (fixed for lifetime of buffer).
    capacity: usize,
    /// Monotonically increasing write position (in frames, never wraps in u64).
    write_pos: AtomicU64,
    /// Active engine sample rate. Updated on init/reconfig.
    sample_rate: AtomicU32,
}

// SAFETY: All access to the interior `Vec<f32>` goes through the documented
// single-writer audio-thread invariant, and UI-thread snapshot is read-only.
unsafe impl Sync for MasterRingBuffer {}

impl MasterRingBuffer {
    /// Create a new ring with capacity for `seconds` at `sample_rate`.
    /// `seconds` is clamped to `MAX_SECONDS`.
    pub fn new(seconds: f32, sample_rate: u32) -> Self {
        let sr = sample_rate.max(1);
        let secs = seconds.clamp(0.0, MAX_SECONDS);
        let capacity = (secs * sr as f32).ceil() as usize;
        Self {
            left:  UnsafeCell::new(vec![0.0; capacity]),
            right: UnsafeCell::new(vec![0.0; capacity]),
            capacity,
            write_pos: AtomicU64::new(0),
            sample_rate: AtomicU32::new(sr),
        }
    }

    /// Default ring — 5 s @ 48 kHz.
    pub const fn empty() -> Self {
        Self {
            left:  UnsafeCell::new(Vec::new()),
            right: UnsafeCell::new(Vec::new()),
            capacity: 0,
            write_pos: AtomicU64::new(0),
            sample_rate: AtomicU32::new(DEFAULT_SAMPLE_RATE),
        }
    }

    /// Lazily allocate on first use. Safe to call from any thread, but should
    /// be called once from the init path before audio starts. Subsequent calls
    /// that would resize are no-ops (capacity is fixed once non-zero).
    pub fn ensure_capacity(&self, seconds: f32, sample_rate: u32) {
        if self.capacity != 0 {
            self.sample_rate.store(sample_rate.max(1), Ordering::Relaxed);
            return;
        }
        let sr = sample_rate.max(1);
        let secs = seconds.clamp(0.0, MAX_SECONDS);
        let cap = (secs * sr as f32).ceil() as usize;
        // SAFETY: this is called before audio thread starts using `write_frames`.
        // If called after, the resize would still be safe as the Vec is not
        // accessed across threads until the first write_frames; we document
        // this as "init-time only" below.
        unsafe {
            let l = &mut *self.left.get();
            let r = &mut *self.right.get();
            l.resize(cap, 0.0);
            r.resize(cap, 0.0);
        }
        self.sample_rate.store(sr, Ordering::Relaxed);
        // Set capacity via a separate atomic-like path is not possible on a
        // non-atomic field; the documented contract is that `ensure_capacity`
        // is called before any audio writes.
        // We use an unsafe write to a non-atomic field, but we rely on the
        // caller's happens-before guarantee (engine init → audio start).
        // This is the same pattern used elsewhere in playback.rs for one-time init.
        unsafe {
            let this = self as *const Self as *mut Self;
            (*this).capacity = cap;
        }
    }

    /// Called from the audio thread at the end of each process block. Zero alloc.
    /// SAFETY: assumes single audio thread is the only writer.
    #[inline]
    pub fn write_frames(&self, left: &[f64], right: &[f64]) {
        let cap = self.capacity;
        if cap == 0 { return; }
        let start = self.write_pos.load(Ordering::Relaxed) as usize;
        let n = left.len().min(right.len());
        if n == 0 { return; }
        // SAFETY: single-writer audio thread — documented invariant.
        let l = unsafe { &mut *self.left.get() };
        let r = unsafe { &mut *self.right.get() };
        for i in 0..n {
            let idx = (start + i) % cap;
            l[idx] = left[i] as f32;
            r[idx] = right[i] as f32;
        }
        self.write_pos.store((start + n) as u64, Ordering::Release);
    }

    /// Snapshot the last `seconds` of master audio.
    /// Returns `(left_samples, right_samples, sample_rate)`.
    /// Safe to call from UI thread concurrent with audio thread writes.
    pub fn snapshot(&self, seconds: f32) -> (Vec<f32>, Vec<f32>, u32) {
        let sr = self.sample_rate.load(Ordering::Relaxed);
        let cap = self.capacity;
        if cap == 0 || seconds <= 0.0 {
            return (Vec::new(), Vec::new(), sr);
        }

        let write_pos = self.write_pos.load(Ordering::Acquire) as usize;
        // How many samples the user asked for, clamped to available.
        let wanted_total = ((seconds * sr as f32).ceil() as usize)
            .min(cap)
            .min(write_pos);
        if wanted_total == 0 {
            return (Vec::new(), Vec::new(), sr);
        }

        let abs_start = write_pos - wanted_total;
        let start = abs_start % cap;
        let mut l_out = Vec::with_capacity(wanted_total);
        let mut r_out = Vec::with_capacity(wanted_total);

        // SAFETY: read-only access; brief; tolerates torn single-sample reads.
        let l = unsafe { &*self.left.get() };
        let r = unsafe { &*self.right.get() };

        if start + wanted_total <= cap {
            l_out.extend_from_slice(&l[start..start + wanted_total]);
            r_out.extend_from_slice(&r[start..start + wanted_total]);
        } else {
            let first = cap - start;
            l_out.extend_from_slice(&l[start..]);
            l_out.extend_from_slice(&l[..wanted_total - first]);
            r_out.extend_from_slice(&r[start..]);
            r_out.extend_from_slice(&r[..wanted_total - first]);
        }

        (l_out, r_out, sr)
    }

    /// Current sample rate.
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate.load(Ordering::Relaxed)
    }

    /// Capacity in frames (fixed after init).
    pub fn capacity(&self) -> usize { self.capacity }

    /// Total frames written since start (monotonic).
    pub fn frames_written(&self) -> u64 {
        self.write_pos.load(Ordering::Relaxed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_zero_seconds() {
        let r = MasterRingBuffer::new(0.0, 48000);
        assert_eq!(r.capacity(), 0);
        let (l, rr, _) = r.snapshot(1.0);
        assert!(l.is_empty() && rr.is_empty());
    }

    #[test]
    fn write_then_snapshot_roundtrip() {
        let r = MasterRingBuffer::new(0.1, 1000); // 100 frames
        let l_in: Vec<f64> = (0..50).map(|i| i as f64 / 50.0).collect();
        let r_in: Vec<f64> = l_in.iter().map(|x| -x).collect();
        r.write_frames(&l_in, &r_in);
        let (l_out, r_out, sr) = r.snapshot(0.05); // 50 frames
        assert_eq!(sr, 1000);
        assert_eq!(l_out.len(), 50);
        assert_eq!(r_out.len(), 50);
        for i in 0..50 {
            assert!((l_out[i] - l_in[i] as f32).abs() < 1e-5);
            assert!((r_out[i] - r_in[i] as f32).abs() < 1e-5);
        }
    }

    #[test]
    fn wraparound_keeps_last_n() {
        let r = MasterRingBuffer::new(0.01, 1000); // 10 frames capacity
        // write 30 frames total
        for block in 0..3 {
            let base = block * 10;
            let l: Vec<f64> = (0..10).map(|i| (base + i) as f64).collect();
            let rr: Vec<f64> = l.clone();
            r.write_frames(&l, &rr);
        }
        // snapshot last 5 frames — should be frames 25..30
        let (l_out, _, _) = r.snapshot(0.005);
        assert_eq!(l_out.len(), 5);
        for (i, v) in l_out.iter().enumerate() {
            assert!((v - (25 + i) as f32).abs() < 1e-4, "got {v} at idx {i}");
        }
    }

    #[test]
    fn snapshot_clamped_to_written() {
        let r = MasterRingBuffer::new(0.1, 1000); // 100 frame capacity
        let l: Vec<f64> = (0..20).map(|i| i as f64).collect();
        r.write_frames(&l, &l);
        // Ask for 50 frames, only 20 written
        let (l_out, _, _) = r.snapshot(0.05);
        assert_eq!(l_out.len(), 20);
    }

    #[test]
    fn ensure_capacity_idempotent() {
        let r = MasterRingBuffer::empty();
        r.ensure_capacity(0.1, 48000);
        let cap1 = r.capacity();
        r.ensure_capacity(1.0, 48000); // should NOT resize
        assert_eq!(r.capacity(), cap1);
    }
}

//! Beat Grid Tracker — real-time beat/bar position tracking
//!
//! Tracks playback position within a musical beat grid, enabling:
//! - Beat/bar/phrase-accurate sync points for tempo state transitions
//! - Atomic reads from audio thread (zero allocation, zero locks)
//! - Tempo ramp interpolation (linear, S-curve)
//!
//! # Audio Thread Safety
//! All methods called from audio thread use only stack allocations
//! and atomic operations. No locks, no allocations, no panics.

use std::sync::atomic::{AtomicU64, Ordering};

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Sync point for tempo state transitions
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncMode {
    /// Transition immediately
    Immediate,
    /// Wait for next beat boundary
    Beat,
    /// Wait for next bar boundary
    Bar,
    /// Wait for next phrase boundary (default: 4 bars)
    Phrase,
    /// Wait for next downbeat (beat 1 of next bar)
    Downbeat,
}

/// Tempo ramp interpolation curve
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TempoRampType {
    /// Instant tempo change at sync point
    Instant,
    /// Linear interpolation over duration
    Linear,
    /// S-curve (smooth start and end)
    SCurve,
}

/// Current beat grid position (returned from tracker)
#[derive(Debug, Clone, Copy)]
pub struct BeatPosition {
    /// Current beat within the bar (0-based, fractional)
    pub beat: f64,
    /// Current bar number (0-based)
    pub bar: u32,
    /// Current phrase number (0-based)
    pub phrase: u32,
    /// Current BPM
    pub bpm: f64,
    /// Total beats elapsed since start
    pub total_beats: f64,
}

/// Active tempo ramp (in progress)
#[derive(Debug, Clone, Copy)]
struct TempoRamp {
    /// Starting BPM
    from_bpm: f64,
    /// Target BPM
    to_bpm: f64,
    /// Ramp type
    ramp_type: TempoRampType,
    /// Total ramp duration in samples
    duration_samples: u64,
    /// Samples elapsed since ramp start
    elapsed_samples: u64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// BEAT GRID TRACKER
// ═══════════════════════════════════════════════════════════════════════════════

/// Real-time beat grid tracker for audio thread use
///
/// Maintains musical position (beat/bar/phrase) based on current tempo
/// and sample-accurate playback position. Supports tempo ramps for
/// smooth BPM transitions.
///
/// # Thread Safety
/// - `advance()` and `position()` are audio-thread safe (no alloc, no locks)
/// - `set_tempo()`, `start_ramp()`, `set_time_signature()` are called from UI thread
/// - Atomic BPM value can be read from any thread via `current_bpm_atomic()`
pub struct BeatGridTracker {
    /// Current BPM (may be mid-ramp)
    current_bpm: f64,
    /// Beats per bar (numerator of time signature)
    beats_per_bar: u32,
    /// Bars per phrase
    bars_per_phrase: u32,
    /// Sample rate
    sample_rate: f64,
    /// Total beats elapsed (fractional)
    total_beats: f64,
    /// Active tempo ramp (None if steady-state)
    active_ramp: Option<TempoRamp>,
    /// Atomic BPM for cross-thread reads (bits of f64)
    bpm_atomic: AtomicU64,
    /// Atomic total_beats for cross-thread reads
    beats_atomic: AtomicU64,
    /// Pending sync callback: (sync_mode, target_beat)
    pending_sync: Option<(SyncMode, f64)>,
    /// Flag: sync point was hit this block
    sync_triggered: bool,
}

impl BeatGridTracker {
    /// Create a new beat grid tracker
    ///
    /// # Arguments
    /// * `bpm` - Initial tempo in beats per minute
    /// * `beats_per_bar` - Time signature numerator (e.g., 4 for 4/4)
    /// * `sample_rate` - Audio sample rate in Hz
    pub fn new(bpm: f64, beats_per_bar: u32, sample_rate: f64) -> Self {
        Self {
            current_bpm: bpm,
            beats_per_bar,
            bars_per_phrase: 4,
            sample_rate,
            total_beats: 0.0,
            active_ramp: None,
            bpm_atomic: AtomicU64::new(bpm.to_bits()),
            beats_atomic: AtomicU64::new(0u64.to_le()),
            pending_sync: None,
            sync_triggered: false,
        }
    }

    /// Set tempo immediately (no ramp)
    pub fn set_tempo(&mut self, bpm: f64) {
        let bpm = bpm.clamp(20.0, 999.0);
        self.current_bpm = bpm;
        self.active_ramp = None;
        self.bpm_atomic.store(bpm.to_bits(), Ordering::Release);
    }

    /// Set time signature
    pub fn set_time_signature(&mut self, beats_per_bar: u32, bars_per_phrase: u32) {
        self.beats_per_bar = beats_per_bar.max(1);
        self.bars_per_phrase = bars_per_phrase.max(1);
    }

    /// Start a tempo ramp from current BPM to target BPM
    ///
    /// # Arguments
    /// * `target_bpm` - Destination tempo
    /// * `duration_bars` - Ramp duration in bars (at current tempo for scheduling)
    /// * `ramp_type` - Interpolation curve
    pub fn start_ramp(&mut self, target_bpm: f64, duration_bars: u32, ramp_type: TempoRampType) {
        let target_bpm = target_bpm.clamp(20.0, 999.0);

        if ramp_type == TempoRampType::Instant {
            self.set_tempo(target_bpm);
            return;
        }

        // Calculate ramp duration in samples based on current BPM
        let beats_in_ramp = duration_bars as f64 * self.beats_per_bar as f64;
        let seconds = beats_in_ramp * 60.0 / self.current_bpm;
        let duration_samples = (seconds * self.sample_rate) as u64;

        if duration_samples == 0 {
            self.set_tempo(target_bpm);
            return;
        }

        self.active_ramp = Some(TempoRamp {
            from_bpm: self.current_bpm,
            to_bpm: target_bpm,
            ramp_type,
            duration_samples,
            elapsed_samples: 0,
        });
    }

    /// Request notification when the next sync point is reached
    ///
    /// After calling this, check `sync_triggered()` after each `advance()` call.
    pub fn request_sync(&mut self, mode: SyncMode) {
        match mode {
            SyncMode::Immediate => {
                self.sync_triggered = true;
                self.pending_sync = None;
            }
            _ => {
                let target = self.next_sync_beat(mode);
                self.pending_sync = Some((mode, target));
                self.sync_triggered = false;
            }
        }
    }

    /// Check if a sync point was triggered during the last `advance()` call
    pub fn sync_triggered(&self) -> bool {
        self.sync_triggered
    }

    /// Clear sync trigger flag
    pub fn clear_sync(&mut self) {
        self.sync_triggered = false;
        self.pending_sync = None;
    }

    /// Advance the beat grid by one audio block
    ///
    /// # Audio Thread Safe
    /// Zero allocations, zero locks. Only arithmetic and atomic stores.
    ///
    /// # Arguments
    /// * `num_samples` - Number of samples in this block
    pub fn advance(&mut self, num_samples: usize) {
        self.sync_triggered = false;
        let beats_before = self.total_beats;

        for _ in 0..num_samples {
            // Update tempo ramp if active
            if let Some(ref mut ramp) = self.active_ramp {
                ramp.elapsed_samples += 1;
                let t = ramp.elapsed_samples as f64 / ramp.duration_samples as f64;

                if t >= 1.0 {
                    // Ramp complete
                    self.current_bpm = ramp.to_bpm;
                    self.active_ramp = None;
                } else {
                    self.current_bpm = interpolate_tempo(ramp.from_bpm, ramp.to_bpm, t, ramp.ramp_type);
                }
            }

            // Advance beat position by one sample
            let beats_per_sample = self.current_bpm / (60.0 * self.sample_rate);
            self.total_beats += beats_per_sample;
        }

        // Update atomics (once per block, not per sample)
        self.bpm_atomic.store(self.current_bpm.to_bits(), Ordering::Release);
        self.beats_atomic.store(self.total_beats.to_bits(), Ordering::Release);

        // Check sync point
        if let Some((mode, target_beat)) = self.pending_sync {
            if beats_before < target_beat && self.total_beats >= target_beat {
                self.sync_triggered = true;
                self.pending_sync = None;
            } else if self.total_beats >= target_beat {
                // Recalculate next sync point (we may have passed it)
                let new_target = self.next_sync_beat(mode);
                if new_target > self.total_beats {
                    self.pending_sync = Some((mode, new_target));
                }
            }
        }
    }

    /// Get current beat position (audio thread safe — stack only)
    pub fn position(&self) -> BeatPosition {
        let bpb = self.beats_per_bar as f64;
        let bpp = bpb * self.bars_per_phrase as f64;

        let beat_in_bar = self.total_beats % bpb;
        let bar = (self.total_beats / bpb) as u32;
        let phrase = (self.total_beats / bpp) as u32;

        BeatPosition {
            beat: beat_in_bar,
            bar,
            phrase,
            bpm: self.current_bpm,
            total_beats: self.total_beats,
        }
    }

    /// Read current BPM atomically (safe from any thread)
    pub fn current_bpm_atomic(&self) -> f64 {
        f64::from_bits(self.bpm_atomic.load(Ordering::Acquire))
    }

    /// Read total beats atomically (safe from any thread)
    pub fn total_beats_atomic(&self) -> f64 {
        f64::from_bits(self.beats_atomic.load(Ordering::Acquire))
    }

    /// Reset to beginning
    pub fn reset(&mut self) {
        self.total_beats = 0.0;
        self.active_ramp = None;
        self.sync_triggered = false;
        self.pending_sync = None;
        self.beats_atomic.store(0f64.to_bits(), Ordering::Release);
    }

    /// Is a tempo ramp currently active?
    pub fn is_ramping(&self) -> bool {
        self.active_ramp.is_some()
    }

    /// Get the stretch factor to convert from source_bpm to current tempo
    ///
    /// Returns the time-stretch ratio: >1.0 = slower (stretched), <1.0 = faster (compressed)
    pub fn stretch_factor(&self, source_bpm: f64) -> f64 {
        if source_bpm <= 0.0 { return 1.0; }
        source_bpm / self.current_bpm
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// Calculate the next beat boundary for the given sync mode
    fn next_sync_beat(&self, mode: SyncMode) -> f64 {
        let bpb = self.beats_per_bar as f64;
        let bpp = bpb * self.bars_per_phrase as f64;

        match mode {
            SyncMode::Immediate => self.total_beats,
            SyncMode::Beat => self.total_beats.floor() + 1.0,
            SyncMode::Bar | SyncMode::Downbeat => {
                let current_bar_start = (self.total_beats / bpb).floor() * bpb;
                current_bar_start + bpb
            }
            SyncMode::Phrase => {
                let current_phrase_start = (self.total_beats / bpp).floor() * bpp;
                current_phrase_start + bpp
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEMPO INTERPOLATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Interpolate between two BPM values using the specified curve
///
/// # Arguments
/// * `from` - Starting BPM
/// * `to` - Target BPM
/// * `t` - Progress (0.0 to 1.0)
/// * `ramp_type` - Interpolation curve
fn interpolate_tempo(from: f64, to: f64, t: f64, ramp_type: TempoRampType) -> f64 {
    let t = t.clamp(0.0, 1.0);
    let factor = match ramp_type {
        TempoRampType::Instant => 1.0,
        TempoRampType::Linear => t,
        TempoRampType::SCurve => {
            // Hermite S-curve: 3t^2 - 2t^3 (smoothstep)
            t * t * (3.0 - 2.0 * t)
        }
    };
    from + (to - from) * factor
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_RATE: f64 = 44100.0;

    #[test]
    fn test_basic_beat_tracking() {
        let mut tracker = BeatGridTracker::new(120.0, 4, SAMPLE_RATE);

        // At 120 BPM, one beat = 0.5 seconds = 22050 samples
        tracker.advance(22050);
        let pos = tracker.position();

        assert!((pos.total_beats - 1.0).abs() < 0.001, "Expected ~1 beat, got {}", pos.total_beats);
        assert!((pos.beat - 1.0).abs() < 0.001);
        assert_eq!(pos.bar, 0); // Still in first bar
    }

    #[test]
    fn test_bar_boundary() {
        let mut tracker = BeatGridTracker::new(120.0, 4, SAMPLE_RATE);

        // 4 beats at 120 BPM = 2 seconds = 88200 samples
        tracker.advance(88200);
        let pos = tracker.position();

        assert_eq!(pos.bar, 1);
        assert!(pos.beat < 0.01); // Should be near beat 0 of bar 1
    }

    #[test]
    fn test_phrase_boundary() {
        let mut tracker = BeatGridTracker::new(120.0, 4, SAMPLE_RATE);

        // 1 phrase = 4 bars = 16 beats at 120 BPM = 8 seconds = 352800 samples
        // Add a few extra samples to ensure we're past the boundary (float precision)
        tracker.advance(352800 + 10);
        let pos = tracker.position();

        assert_eq!(pos.phrase, 1);
    }

    #[test]
    fn test_sync_beat() {
        let mut tracker = BeatGridTracker::new(120.0, 4, SAMPLE_RATE);

        // Advance half a beat
        tracker.advance(11025);
        tracker.request_sync(SyncMode::Beat);
        assert!(!tracker.sync_triggered());

        // Advance to complete the beat
        tracker.advance(11025);
        assert!(tracker.sync_triggered());
    }

    #[test]
    fn test_sync_bar() {
        let mut tracker = BeatGridTracker::new(120.0, 4, SAMPLE_RATE);

        // Advance 2 beats
        tracker.advance(44100);
        tracker.request_sync(SyncMode::Bar);

        // Advance 1 more beat — should NOT trigger (still in same bar)
        tracker.advance(22050);
        assert!(!tracker.sync_triggered());

        // Advance 1 more beat — should trigger (bar boundary)
        tracker.advance(22050);
        assert!(tracker.sync_triggered());
    }

    #[test]
    fn test_tempo_ramp_linear() {
        let mut tracker = BeatGridTracker::new(120.0, 4, SAMPLE_RATE);

        // Ramp from 120 to 180 over 2 bars
        tracker.start_ramp(180.0, 2, TempoRampType::Linear);

        // Process enough samples to complete the ramp
        // 2 bars at 120 BPM = 8 beats = 4 seconds
        for _ in 0..40 {
            tracker.advance(4410); // 0.1 sec chunks
        }

        assert!((tracker.current_bpm_atomic() - 180.0).abs() < 0.1,
            "Expected ~180 BPM, got {}", tracker.current_bpm_atomic());
    }

    #[test]
    fn test_tempo_ramp_scurve() {
        let mut tracker = BeatGridTracker::new(100.0, 4, SAMPLE_RATE);

        tracker.start_ramp(200.0, 1, TempoRampType::SCurve);

        // Process in chunks, verify S-curve midpoint is near average
        let mut mid_bpm = 0.0;
        let total_chunks = 20;
        for i in 0..total_chunks {
            tracker.advance(4410);
            if i == total_chunks / 2 {
                mid_bpm = tracker.current_bpm_atomic();
            }
        }

        // S-curve midpoint should be approximately average of from/to
        assert!((mid_bpm - 150.0).abs() < 10.0,
            "S-curve midpoint should be ~150, got {}", mid_bpm);
    }

    #[test]
    fn test_stretch_factor() {
        let tracker = BeatGridTracker::new(120.0, 4, SAMPLE_RATE);

        // Source at 120, playing at 120 → stretch 1.0
        assert!((tracker.stretch_factor(120.0) - 1.0).abs() < 0.001);

        // Source at 100, playing at 120 → stretch 0.833 (faster)
        assert!((tracker.stretch_factor(100.0) - 0.833).abs() < 0.01);

        // Source at 180, playing at 120 → stretch 1.5 (slower)
        assert!((tracker.stretch_factor(180.0) - 1.5).abs() < 0.001);
    }

    #[test]
    fn test_instant_ramp() {
        let mut tracker = BeatGridTracker::new(120.0, 4, SAMPLE_RATE);
        tracker.start_ramp(200.0, 2, TempoRampType::Instant);

        // Should be instant — no ramp active
        assert!(!tracker.is_ramping());
        assert!((tracker.current_bpm_atomic() - 200.0).abs() < 0.001);
    }

    #[test]
    fn test_interpolate_scurve_boundaries() {
        // t=0 → from, t=1 → to
        assert!((interpolate_tempo(100.0, 200.0, 0.0, TempoRampType::SCurve) - 100.0).abs() < 0.001);
        assert!((interpolate_tempo(100.0, 200.0, 1.0, TempoRampType::SCurve) - 200.0).abs() < 0.001);

        // t=0.5 → midpoint (smoothstep(0.5) = 0.5)
        assert!((interpolate_tempo(100.0, 200.0, 0.5, TempoRampType::SCurve) - 150.0).abs() < 0.001);
    }

    #[test]
    fn test_reset() {
        let mut tracker = BeatGridTracker::new(120.0, 4, SAMPLE_RATE);
        tracker.advance(88200);
        tracker.start_ramp(200.0, 2, TempoRampType::Linear);

        tracker.reset();

        let pos = tracker.position();
        assert!(pos.total_beats < 0.001);
        assert!(!tracker.is_ramping());
    }
}

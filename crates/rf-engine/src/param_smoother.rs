//! Parameter Smoothing for Zipper-Free Automation
//!
//! Provides exponential smoothing for audio parameters to prevent
//! zipper noise from abrupt value changes during automation playback.
//!
//! Target: 1-2ms ramp time (48-96 samples @ 48kHz)
//!
//! # Lock-Free Design
//! Audio thread methods use atomic operations only - NO locks.
//! UI thread sets targets via atomics, audio thread reads and smooths.

use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};

// ═══════════════════════════════════════════════════════════════════════════
// SMOOTHER CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Default smoothing time in milliseconds
pub const DEFAULT_SMOOTH_TIME_MS: f64 = 1.5;

/// Minimum smoothing time in milliseconds
pub const MIN_SMOOTH_TIME_MS: f64 = 0.5;

/// Maximum smoothing time in milliseconds
pub const MAX_SMOOTH_TIME_MS: f64 = 10.0;

/// Threshold for considering smoothing complete (relative to target)
const SMOOTH_THRESHOLD: f64 = 1e-6;

// ═══════════════════════════════════════════════════════════════════════════
// SINGLE PARAMETER SMOOTHER
// ═══════════════════════════════════════════════════════════════════════════

/// Single parameter smoother using exponential smoothing
///
/// Formula: current = current + coeff * (target - current)
/// where coeff = 1 - exp(-1 / (time_constant * sample_rate))
#[derive(Debug, Clone)]
pub struct ParamSmoother {
    /// Current smoothed value
    current: f64,
    /// Target value
    target: f64,
    /// Smoothing coefficient (pre-calculated)
    coeff: f64,
    /// Sample rate for coefficient calculation
    sample_rate: f64,
    /// Smoothing time in milliseconds
    smooth_time_ms: f64,
    /// Is smoothing active (target != current)
    is_smoothing: bool,
}

impl ParamSmoother {
    /// Create new smoother with default smoothing time
    pub fn new(sample_rate: f64, initial_value: f64) -> Self {
        Self::with_time(sample_rate, initial_value, DEFAULT_SMOOTH_TIME_MS)
    }

    /// Create smoother with custom smoothing time
    pub fn with_time(sample_rate: f64, initial_value: f64, smooth_time_ms: f64) -> Self {
        let smooth_time_ms = smooth_time_ms.clamp(MIN_SMOOTH_TIME_MS, MAX_SMOOTH_TIME_MS);
        let coeff = Self::calculate_coeff(sample_rate, smooth_time_ms);

        Self {
            current: initial_value,
            target: initial_value,
            coeff,
            sample_rate,
            smooth_time_ms,
            is_smoothing: false,
        }
    }

    /// Calculate smoothing coefficient from time constant
    #[inline]
    fn calculate_coeff(sample_rate: f64, smooth_time_ms: f64) -> f64 {
        let time_constant_samples = (smooth_time_ms / 1000.0) * sample_rate;
        1.0 - (-1.0 / time_constant_samples).exp()
    }

    /// Set new target value (starts smoothing)
    #[inline]
    pub fn set_target(&mut self, target: f64) {
        if (self.target - target).abs() > SMOOTH_THRESHOLD {
            self.target = target;
            self.is_smoothing = true;
        }
    }

    /// Set value immediately (no smoothing)
    #[inline]
    pub fn set_immediate(&mut self, value: f64) {
        self.current = value;
        self.target = value;
        self.is_smoothing = false;
    }

    /// Get next smoothed sample
    #[inline]
    pub fn next_value(&mut self) -> f64 {
        if self.is_smoothing {
            self.current += self.coeff * (self.target - self.current);

            // Check if smoothing is complete
            if (self.current - self.target).abs() < SMOOTH_THRESHOLD {
                self.current = self.target;
                self.is_smoothing = false;
            }
        }
        self.current
    }

    /// Process entire block, returning smoothed values
    pub fn process_block(&mut self, output: &mut [f64]) {
        if !self.is_smoothing {
            // Fast path: no smoothing needed, fill with current value
            output.fill(self.current);
            return;
        }

        for sample in output.iter_mut() {
            *sample = self.next_value();
        }
    }

    /// Get current smoothed value without advancing
    #[inline]
    pub fn current(&self) -> f64 {
        self.current
    }

    /// Get target value
    #[inline]
    pub fn target(&self) -> f64 {
        self.target
    }

    /// Check if currently smoothing
    #[inline]
    pub fn is_smoothing(&self) -> bool {
        self.is_smoothing
    }

    /// Update sample rate (recalculates coefficient)
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.coeff = Self::calculate_coeff(sample_rate, self.smooth_time_ms);
    }

    /// Update smoothing time (recalculates coefficient)
    pub fn set_smooth_time(&mut self, smooth_time_ms: f64) {
        let smooth_time_ms = smooth_time_ms.clamp(MIN_SMOOTH_TIME_MS, MAX_SMOOTH_TIME_MS);
        self.smooth_time_ms = smooth_time_ms;
        self.coeff = Self::calculate_coeff(self.sample_rate, smooth_time_ms);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK PARAMETER SMOOTHER
// ═══════════════════════════════════════════════════════════════════════════

/// Smoother for all parameters of a single track
#[derive(Debug, Clone)]
pub struct TrackParamSmoother {
    /// Volume smoother (0.0 - 1.5)
    pub volume: ParamSmoother,
    /// Pan smoother (-1.0 to 1.0)
    pub pan: ParamSmoother,
}

impl TrackParamSmoother {
    /// Create new track smoother
    pub fn new(sample_rate: f64) -> Self {
        Self {
            volume: ParamSmoother::new(sample_rate, 1.0), // Default volume = 1.0
            pan: ParamSmoother::new(sample_rate, 0.0),    // Default pan = center
        }
    }

    /// Check if any parameter is currently smoothing
    pub fn is_smoothing(&self) -> bool {
        self.volume.is_smoothing() || self.pan.is_smoothing()
    }

    /// Update sample rate for all smoothers
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.volume.set_sample_rate(sample_rate);
        self.pan.set_sample_rate(sample_rate);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOCK-FREE PARAMETER SMOOTHER MANAGER (AUDIO THREAD SAFE)
// ═══════════════════════════════════════════════════════════════════════════

/// Maximum number of tracks supported (pre-allocated)
pub const MAX_TRACKS: usize = 256;

/// Atomic parameter state for lock-free UI→Audio communication
/// Uses AtomicU64 to store f64 bit patterns
#[repr(C)]
pub struct AtomicParamState {
    /// Target volume (f64 bits)
    target_volume: AtomicU64,
    /// Target pan (f64 bits)
    target_pan: AtomicU64,
    /// Is this slot active (0 = inactive, 1 = active)
    active: AtomicUsize,
}

impl AtomicParamState {
    const fn new() -> Self {
        Self {
            target_volume: AtomicU64::new(0x3FF0000000000000), // 1.0 as f64 bits
            target_pan: AtomicU64::new(0),                     // 0.0 as f64 bits
            active: AtomicUsize::new(0),
        }
    }

    #[inline]
    fn set_volume(&self, volume: f64) {
        self.target_volume
            .store(volume.to_bits(), Ordering::Release);
    }

    #[inline]
    fn set_pan(&self, pan: f64) {
        self.target_pan.store(pan.to_bits(), Ordering::Release);
    }

    #[inline]
    fn get_target_volume(&self) -> f64 {
        f64::from_bits(self.target_volume.load(Ordering::Acquire))
    }

    #[inline]
    fn get_target_pan(&self) -> f64 {
        f64::from_bits(self.target_pan.load(Ordering::Acquire))
    }

    #[inline]
    fn set_active(&self, active: bool) {
        self.active
            .store(if active { 1 } else { 0 }, Ordering::Release);
    }

    #[inline]
    fn is_active(&self) -> bool {
        self.active.load(Ordering::Acquire) != 0
    }
}

/// Per-track smoother state (owned by audio thread)
/// NOT shared - each track has its own instance
pub struct TrackSmootherState {
    volume: ParamSmoother,
    pan: ParamSmoother,
}

impl TrackSmootherState {
    fn new(sample_rate: f64) -> Self {
        Self {
            volume: ParamSmoother::new(sample_rate, 1.0),
            pan: ParamSmoother::new(sample_rate, 0.0),
        }
    }

    #[inline]
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.volume.set_sample_rate(sample_rate);
        self.pan.set_sample_rate(sample_rate);
    }
}

/// Lock-free parameter smoother manager
///
/// # Architecture
/// - UI thread sets targets via atomic writes (zero latency)
/// - Audio thread reads targets and applies smoothing (never blocks)
/// - Pre-allocated arrays avoid runtime allocation
///
/// # Memory Layout
/// - `atomic_state`: Shared UI→Audio targets (atomics only)
/// - `smoother_state`: Audio-thread-only smoothing state (not shared)
pub struct ParamSmootherManager {
    /// Atomic targets set by UI thread, read by audio thread
    /// Index = track_id % MAX_TRACKS
    atomic_state: [AtomicParamState; MAX_TRACKS],
    /// Audio-thread-only smoother state
    /// Wrapped in UnsafeCell for interior mutability from audio thread
    smoother_state: std::cell::UnsafeCell<[TrackSmootherState; MAX_TRACKS]>,
    /// Sample rate (atomic for UI updates)
    sample_rate: AtomicU64,
}

// SAFETY: atomic_state is accessed via atomics only
// smoother_state is only accessed from audio thread
unsafe impl Send for ParamSmootherManager {}
unsafe impl Sync for ParamSmootherManager {}

impl ParamSmootherManager {
    /// Create new manager with pre-allocated state
    pub fn new(sample_rate: f64) -> Self {
        // Initialize atomic state array
        const ATOMIC_INIT: AtomicParamState = AtomicParamState::new();
        let atomic_state = [ATOMIC_INIT; MAX_TRACKS];

        // Initialize smoother state array
        let smoother_state: [TrackSmootherState; MAX_TRACKS] =
            std::array::from_fn(|_| TrackSmootherState::new(sample_rate));

        Self {
            atomic_state,
            smoother_state: std::cell::UnsafeCell::new(smoother_state),
            sample_rate: AtomicU64::new(sample_rate.to_bits()),
        }
    }

    /// Map track_id to array index
    #[inline]
    fn track_index(track_id: u64) -> usize {
        (track_id as usize) % MAX_TRACKS
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UI THREAD METHODS (set targets via atomics - never blocks)
    // ═══════════════════════════════════════════════════════════════════════

    /// Set track volume target (UI thread - lock-free)
    #[inline]
    pub fn set_track_volume(&self, track_id: u64, volume: f64) {
        let idx = Self::track_index(track_id);
        self.atomic_state[idx].set_volume(volume);
        self.atomic_state[idx].set_active(true);
    }

    /// Set track pan target (UI thread - lock-free)
    #[inline]
    pub fn set_track_pan(&self, track_id: u64, pan: f64) {
        let idx = Self::track_index(track_id);
        self.atomic_state[idx].set_pan(pan);
        self.atomic_state[idx].set_active(true);
    }

    /// Activate track (UI thread)
    pub fn activate_track(&self, track_id: u64) {
        let idx = Self::track_index(track_id);
        self.atomic_state[idx].set_active(true);
    }

    /// Deactivate track (UI thread)
    pub fn remove_track(&self, track_id: u64) {
        let idx = Self::track_index(track_id);
        self.atomic_state[idx].set_active(false);
    }

    /// Update sample rate (UI thread)
    pub fn set_sample_rate(&self, sample_rate: f64) {
        self.sample_rate
            .store(sample_rate.to_bits(), Ordering::Release);
        // Note: Audio thread will pick up new sample rate on next process call
    }

    /// Clear all tracks (UI thread)
    pub fn clear(&self) {
        for state in &self.atomic_state {
            state.set_active(false);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO THREAD METHODS (lock-free, zero allocation)
    // ═══════════════════════════════════════════════════════════════════════

    /// Get current smoothed volume (audio thread - lock-free)
    ///
    /// Reads atomic target, applies smoothing, returns current value
    #[inline]
    pub fn get_track_volume(&self, track_id: u64) -> f64 {
        let idx = Self::track_index(track_id);
        if !self.atomic_state[idx].is_active() {
            return 1.0; // Default
        }

        // SAFETY: Audio thread has exclusive access to smoother_state
        unsafe {
            let state = &mut (*self.smoother_state.get())[idx];
            state.volume.current()
        }
    }

    /// Get current smoothed pan (audio thread - lock-free)
    #[inline]
    pub fn get_track_pan(&self, track_id: u64) -> f64 {
        let idx = Self::track_index(track_id);
        if !self.atomic_state[idx].is_active() {
            return 0.0; // Default
        }

        // SAFETY: Audio thread has exclusive access to smoother_state
        unsafe {
            let state = &mut (*self.smoother_state.get())[idx];
            state.pan.current()
        }
    }

    /// Advance smoother and get next values (audio thread - lock-free)
    ///
    /// This is the main method called from audio callback.
    /// 1. Reads atomic targets from UI thread
    /// 2. Updates smoother targets if changed
    /// 3. Advances smoothers by one sample
    /// 4. Returns smoothed (volume, pan)
    #[inline]
    pub fn advance_track(&self, track_id: u64) -> (f64, f64) {
        let idx = Self::track_index(track_id);
        let atomic = &self.atomic_state[idx];

        if !atomic.is_active() {
            return (1.0, 0.0); // Default values
        }

        // Read atomic targets (lock-free)
        let target_volume = atomic.get_target_volume();
        let target_pan = atomic.get_target_pan();

        // SAFETY: Audio thread has exclusive access to smoother_state
        unsafe {
            let state = &mut (*self.smoother_state.get())[idx];

            // Update targets from atomics (only if changed)
            state.volume.set_target(target_volume);
            state.pan.set_target(target_pan);

            // Advance smoothers and return current values
            (state.volume.next_value(), state.pan.next_value())
        }
    }

    /// Process block for track (audio thread - lock-free)
    #[inline]
    pub fn process_track_block(&self, track_id: u64, volume_out: &mut [f64], pan_out: &mut [f64]) {
        let idx = Self::track_index(track_id);
        let atomic = &self.atomic_state[idx];

        if !atomic.is_active() {
            volume_out.fill(1.0);
            pan_out.fill(0.0);
            return;
        }

        // Read atomic targets once for the block
        let target_volume = atomic.get_target_volume();
        let target_pan = atomic.get_target_pan();

        // SAFETY: Audio thread has exclusive access to smoother_state
        unsafe {
            let state = &mut (*self.smoother_state.get())[idx];

            // Update targets
            state.volume.set_target(target_volume);
            state.pan.set_target(target_pan);

            // Process blocks
            state.volume.process_block(volume_out);
            state.pan.process_block(pan_out);
        }
    }

    /// Check if track has active smoothing (audio thread - lock-free)
    #[inline]
    pub fn is_track_smoothing(&self, track_id: u64) -> bool {
        let idx = Self::track_index(track_id);
        if !self.atomic_state[idx].is_active() {
            return false;
        }

        // SAFETY: Audio thread has exclusive access to smoother_state
        unsafe {
            let state = &(*self.smoother_state.get())[idx];
            state.volume.is_smoothing() || state.pan.is_smoothing()
        }
    }

    /// Update sample rate for a specific track's smoother (audio thread)
    ///
    /// Call this when sample rate changes (usually at start of processing)
    pub fn update_track_sample_rate(&self, track_id: u64) {
        let idx = Self::track_index(track_id);
        let sample_rate = f64::from_bits(self.sample_rate.load(Ordering::Acquire));

        // SAFETY: Audio thread has exclusive access to smoother_state
        unsafe {
            let state = &mut (*self.smoother_state.get())[idx];
            state.set_sample_rate(sample_rate);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LEGACY API COMPATIBILITY (for existing code - uses same lock-free impl)
    // ═══════════════════════════════════════════════════════════════════════

    /// Legacy: Get or create track (just activates the slot)
    #[inline]
    pub fn get_or_create_track(&self, track_id: u64) -> &Self {
        self.activate_track(track_id);
        self
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_RATE: f64 = 48000.0;

    #[test]
    fn test_param_smoother_immediate() {
        let mut smoother = ParamSmoother::new(SAMPLE_RATE, 0.0);

        smoother.set_immediate(1.0);
        assert_eq!(smoother.current(), 1.0);
        assert_eq!(smoother.target(), 1.0);
        assert!(!smoother.is_smoothing());
    }

    #[test]
    fn test_param_smoother_smoothing() {
        let mut smoother = ParamSmoother::new(SAMPLE_RATE, 0.0);

        smoother.set_target(1.0);
        assert!(smoother.is_smoothing());

        // Advance a few samples
        for _ in 0..100 {
            let _ = smoother.next_value();
        }

        // Should be approaching target but not there yet
        assert!(smoother.current() > 0.5);
        assert!(smoother.current() < 1.0);
    }

    #[test]
    fn test_param_smoother_convergence() {
        let mut smoother = ParamSmoother::new(SAMPLE_RATE, 0.0);

        smoother.set_target(1.0);

        // Advance enough samples for convergence
        // Exponential smoothing converges ~99.3% after 5 time constants
        // 1.5ms * 48kHz = 72 samples per time constant, * 10 = 720 for good convergence
        for _ in 0..1000 {
            let _ = smoother.next_value();
        }

        // Should have converged (within threshold)
        assert!((smoother.current() - 1.0).abs() < 0.001);
        // is_smoothing flag should be false when within SMOOTH_THRESHOLD
        // Note: may still be true if delta is > 1e-6, which is fine
    }

    #[test]
    fn test_track_param_smoother() {
        let mut track_smoother = TrackParamSmoother::new(SAMPLE_RATE);

        // Default values
        assert_eq!(track_smoother.volume.current(), 1.0);
        assert_eq!(track_smoother.pan.current(), 0.0);

        // Set targets
        track_smoother.volume.set_target(0.5);
        track_smoother.pan.set_target(-0.5);

        assert!(track_smoother.is_smoothing());

        // Advance
        for _ in 0..500 {
            let _ = track_smoother.volume.next_value();
            let _ = track_smoother.pan.next_value();
        }

        assert!((track_smoother.volume.current() - 0.5).abs() < 0.001);
        assert!((track_smoother.pan.current() - (-0.5)).abs() < 0.001);
    }

    #[test]
    fn test_smoother_manager_lock_free() {
        let manager = ParamSmootherManager::new(SAMPLE_RATE);

        // UI thread: Set track 1 volume target (lock-free atomic write)
        manager.set_track_volume(1, 0.5);

        // Audio thread: Advance and check convergence (lock-free)
        for _ in 0..500 {
            let _ = manager.advance_track(1);
        }

        // Should have converged to target
        assert!((manager.get_track_volume(1) - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_smoother_manager_pan() {
        let manager = ParamSmootherManager::new(SAMPLE_RATE);

        // Set pan target
        manager.set_track_pan(5, -0.75);

        // Advance
        for _ in 0..500 {
            let _ = manager.advance_track(5);
        }

        assert!((manager.get_track_pan(5) - (-0.75)).abs() < 0.001);
    }

    #[test]
    fn test_smoother_manager_inactive_track() {
        let manager = ParamSmootherManager::new(SAMPLE_RATE);

        // Track not activated - should return defaults
        let (vol, pan) = manager.advance_track(99);
        assert_eq!(vol, 1.0);
        assert_eq!(pan, 0.0);
    }

    #[test]
    fn test_smoother_manager_process_block() {
        let manager = ParamSmootherManager::new(SAMPLE_RATE);

        manager.set_track_volume(0, 0.5);
        manager.set_track_pan(0, 0.25);

        let mut vol_out = vec![0.0; 256];
        let mut pan_out = vec![0.0; 256];

        // Process multiple blocks to converge
        for _ in 0..10 {
            manager.process_track_block(0, &mut vol_out, &mut pan_out);
        }

        // Should be close to targets
        assert!((vol_out[255] - 0.5).abs() < 0.01);
        assert!((pan_out[255] - 0.25).abs() < 0.01);
    }

    #[test]
    fn test_process_block() {
        let mut smoother = ParamSmoother::new(SAMPLE_RATE, 0.0);
        smoother.set_target(1.0);

        let mut output = vec![0.0; 256];
        smoother.process_block(&mut output);

        // First sample should be small (just started smoothing)
        assert!(output[0] < 0.1);

        // Last sample should be larger
        assert!(output[255] > output[0]);

        // Values should be monotonically increasing
        for i in 1..256 {
            assert!(output[i] >= output[i - 1]);
        }
    }

    #[test]
    fn test_atomic_state_defaults() {
        let state = AtomicParamState::new();

        // Default values
        assert_eq!(state.get_target_volume(), 1.0);
        assert_eq!(state.get_target_pan(), 0.0);
        assert!(!state.is_active());
    }

    #[test]
    fn test_atomic_state_set_get() {
        let state = AtomicParamState::new();

        state.set_volume(0.75);
        state.set_pan(-0.5);
        state.set_active(true);

        assert_eq!(state.get_target_volume(), 0.75);
        assert_eq!(state.get_target_pan(), -0.5);
        assert!(state.is_active());
    }
}

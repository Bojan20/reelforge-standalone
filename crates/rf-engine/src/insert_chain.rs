//! Insert Effect Chain
//!
//! Provides per-channel effect insert slots with:
//! - 8 insert slots per channel (4 pre + 4 post fader)
//! - Pre/post fader positioning
//! - Bypass per slot
//! - Latency compensation
//! - Lock-free parameter updates via ring buffer
//! - P10.0.1: Per-processor metering (input/output levels)

use rf_core::Sample;
use rf_dsp::delay_compensation::LatencySamples;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

// =============================================================================
// P10.0.1: PER-PROCESSOR METERING
// =============================================================================

/// Metering data for a single processor (input → output levels)
#[derive(Debug, Clone, Copy, Default)]
pub struct ProcessorMetering {
    /// Input peak level (left channel)
    pub input_peak_l: f64,
    /// Input peak level (right channel)
    pub input_peak_r: f64,
    /// Input RMS level (left channel)
    pub input_rms_l: f64,
    /// Input RMS level (right channel)
    pub input_rms_r: f64,

    /// Output peak level (left channel)
    pub output_peak_l: f64,
    /// Output peak level (right channel)
    pub output_peak_r: f64,
    /// Output RMS level (left channel)
    pub output_rms_l: f64,
    /// Output RMS level (right channel)
    pub output_rms_r: f64,

    /// Gain reduction (for dynamics processors, dB)
    pub gain_reduction_db: f64,

    /// Processing load (percentage, 0-100)
    pub load_percent: f64,
}

impl ProcessorMetering {
    /// Create new metering instance (all zeros)
    pub fn new() -> Self {
        Self::default()
    }

    /// Reset all meters to zero
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// Update from stereo buffers (calculate peak + RMS)
    pub fn update_from_buffers(&mut self, left: &[Sample], right: &[Sample]) {
        // Calculate input levels
        self.input_peak_l = left.iter().map(|s| s.abs()).fold(0.0, f64::max);
        self.input_peak_r = right.iter().map(|s| s.abs()).fold(0.0, f64::max);

        self.input_rms_l = (left.iter().map(|s| s * s).sum::<f64>() / left.len() as f64).sqrt();
        self.input_rms_r = (right.iter().map(|s| s * s).sum::<f64>() / right.len() as f64).sqrt();

        // Output levels will be updated after processing
    }

    /// Update output levels after processing
    pub fn update_output_levels(&mut self, left: &[Sample], right: &[Sample]) {
        self.output_peak_l = left.iter().map(|s| s.abs()).fold(0.0, f64::max);
        self.output_peak_r = right.iter().map(|s| s.abs()).fold(0.0, f64::max);

        self.output_rms_l = (left.iter().map(|s| s * s).sum::<f64>() / left.len() as f64).sqrt();
        self.output_rms_r = (right.iter().map(|s| s * s).sum::<f64>() / right.len() as f64).sqrt();
    }

    /// Calculate gain reduction in dB (input vs output)
    pub fn calculate_gain_reduction(&mut self) {
        let input_peak = self.input_peak_l.max(self.input_peak_r);
        let output_peak = self.output_peak_l.max(self.output_peak_r);

        if input_peak > 1e-10 && output_peak > 1e-10 {
            self.gain_reduction_db = 20.0 * (output_peak / input_peak).log10();
        } else {
            self.gain_reduction_db = 0.0;
        }
    }
}

// ============ Bypass Fade Configuration ============

/// Bypass fade time in milliseconds (click-free transitions)
const BYPASS_FADE_MS: f64 = 5.0;

/// Default sample rate for coefficient calculation
const DEFAULT_SAMPLE_RATE: f64 = 48000.0;

// ============ Lock-Free Parameter Change ============

/// Lock-free parameter change message for insert processors.
/// Sent from UI thread via ring buffer, consumed by audio thread.
#[derive(Clone, Copy, Debug)]
pub struct InsertParamChange {
    /// Target track ID (0 = master bus)
    pub track_id: u64,
    /// Insert slot index (0-7)
    pub slot_index: u8,
    /// Parameter index within processor
    pub param_index: u16,
    /// New parameter value
    pub value: f64,
}

impl InsertParamChange {
    pub fn new(track_id: u64, slot_index: usize, param_index: usize, value: f64) -> Self {
        Self {
            track_id,
            slot_index: slot_index as u8,
            param_index: param_index as u16,
            value,
        }
    }
}

// ============ Insert Slot ============

/// Maximum insert slots per channel (4 pre-fader + 4 post-fader)
pub const MAX_INSERT_SLOTS: usize = 8;

/// Insert slot position
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InsertPosition {
    /// Before fader (affects send levels)
    #[default]
    PreFader,
    /// After fader
    PostFader,
}

/// Maximum buffer size for wet/dry blending (pre-allocated to avoid audio thread allocations)
const MAX_BLEND_BUFFER_SIZE: usize = 8192;

/// Single insert slot
pub struct InsertSlot {
    /// The effect processor (trait object)
    processor: Option<Box<dyn InsertProcessor>>,
    /// Bypass state (target, set from UI)
    bypassed: AtomicBool,
    /// Position (pre/post fader)
    position: InsertPosition,
    /// Slot index (0-7)
    #[allow(dead_code)]
    index: usize,
    /// Latency introduced by this slot
    latency: LatencySamples,
    /// Wet/dry mix (0.0 = dry, 1.0 = wet)
    mix: AtomicU64,
    /// Pre-allocated buffer for wet/dry blending (left channel)
    /// Avoids heap allocation in audio thread
    dry_buffer_l: Box<[Sample; MAX_BLEND_BUFFER_SIZE]>,
    /// Pre-allocated buffer for wet/dry blending (right channel)
    dry_buffer_r: Box<[Sample; MAX_BLEND_BUFFER_SIZE]>,
    // ═══ Bypass Fade (Click-Free Transitions) ═══
    /// Current bypass gain (0.0 = bypassed, 1.0 = active)
    /// Smoothly transitions between states
    bypass_gain: f64,
    /// Exponential smoothing coefficient for bypass fade
    bypass_coeff: f64,
    /// Sample rate for coefficient calculation
    sample_rate: f64,
    // ═══ Sidechain (P0.5) ═══
    /// Sidechain source track ID (-1 = internal/disabled)
    sidechain_source: i64,
    // ═══ P10.0.1: Per-Processor Metering ═══
    /// Real-time metering data (input/output levels, GR, load)
    metering: ProcessorMetering,
}

impl InsertSlot {
    /// Calculate exponential smoothing coefficient from fade time
    #[inline]
    fn calculate_bypass_coeff(sample_rate: f64) -> f64 {
        let time_constant_samples = (BYPASS_FADE_MS / 1000.0) * sample_rate;
        if time_constant_samples <= 0.0 {
            1.0
        } else {
            1.0 - (-1.0 / time_constant_samples).exp()
        }
    }

    pub fn new(index: usize) -> Self {
        Self {
            processor: None,
            bypassed: AtomicBool::new(false),
            position: InsertPosition::PreFader,
            index,
            latency: 0,
            mix: AtomicU64::new(1.0_f64.to_bits()),
            // Pre-allocate buffers to avoid audio thread allocation
            dry_buffer_l: Box::new([0.0; MAX_BLEND_BUFFER_SIZE]),
            dry_buffer_r: Box::new([0.0; MAX_BLEND_BUFFER_SIZE]),
            // Sidechain
            sidechain_source: -1, // Default: internal
            // Bypass fade: start active (gain = 1.0)
            bypass_gain: 1.0,
            bypass_coeff: Self::calculate_bypass_coeff(DEFAULT_SAMPLE_RATE),
            sample_rate: DEFAULT_SAMPLE_RATE,
            // P10.0.1: Metering
            metering: ProcessorMetering::new(),
        }
    }

    /// Load a processor into this slot
    pub fn load(&mut self, processor: Box<dyn InsertProcessor>) {
        self.latency = processor.latency();
        self.processor = Some(processor);
    }

    /// Unload the processor
    pub fn unload(&mut self) -> Option<Box<dyn InsertProcessor>> {
        self.latency = 0;
        self.processor.take()
    }

    /// Check if slot has a processor
    pub fn is_loaded(&self) -> bool {
        self.processor.is_some()
    }

    /// Set bypass state
    pub fn set_bypass(&self, bypass: bool) {
        self.bypassed.store(bypass, Ordering::Relaxed);
    }

    /// Get bypass state
    pub fn is_bypassed(&self) -> bool {
        self.bypassed.load(Ordering::Relaxed)
    }

    /// Set wet/dry mix
    pub fn set_mix(&self, mix: f64) {
        self.mix
            .store(mix.clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
    }

    /// Get wet/dry mix
    pub fn mix(&self) -> f64 {
        f64::from_bits(self.mix.load(Ordering::Relaxed))
    }

    /// Set position
    pub fn set_position(&mut self, position: InsertPosition) {
        self.position = position;
    }

    /// Get position
    pub fn position(&self) -> InsertPosition {
        self.position
    }

    /// Get latency
    pub fn latency(&self) -> LatencySamples {
        if self.is_bypassed() { 0 } else { self.latency }
    }

    /// Check if bypass fade is still in transition
    #[inline]
    #[allow(dead_code)]
    fn is_fading(&self) -> bool {
        let target = if self.is_bypassed() { 0.0 } else { 1.0 };
        (self.bypass_gain - target).abs() > 1e-6
    }

    /// Process audio through this slot
    ///
    /// # Audio Thread Safety
    /// This method uses pre-allocated buffers for wet/dry blending,
    /// avoiding heap allocations in the audio thread.
    ///
    /// # Click-Free Bypass
    /// Uses exponential smoothing for bypass transitions (~5ms fade)
    #[inline]
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        // Determine target bypass gain (0.0 = bypassed, 1.0 = active)
        let target_bypass_gain = if self.is_bypassed() { 0.0 } else { 1.0 };

        // Fast path: fully bypassed and not fading - skip entirely
        if self.bypass_gain < 1e-6 && target_bypass_gain < 1e-6 {
            self.metering.reset(); // P10.0.1: Clear metering when bypassed
            return;
        }

        // Get mix before borrowing processor
        let mix = self.mix();
        let len = left.len().min(right.len()).min(MAX_BLEND_BUFFER_SIZE);

        if let Some(ref mut processor) = self.processor {
            // P10.0.1: Update input metering BEFORE processing
            self.metering.update_from_buffers(&left[..len], &right[..len]);

            // Store dry signal in pre-allocated buffers (always needed for fade)
            self.dry_buffer_l[..len].copy_from_slice(&left[..len]);
            self.dry_buffer_r[..len].copy_from_slice(&right[..len]);

            // Process wet signal
            processor.process_stereo(&mut left[..len], &mut right[..len]);

            // Apply bypass fade with wet/dry mix per sample
            let coeff = self.bypass_coeff;
            for i in 0..len {
                // Update bypass gain (exponential smoothing)
                self.bypass_gain += coeff * (target_bypass_gain - self.bypass_gain);

                // Calculate effective wet amount (bypass_gain * mix)
                let effective_wet = self.bypass_gain * mix;
                let effective_dry = 1.0 - effective_wet;

                // Blend dry and wet
                left[i] = self.dry_buffer_l[i] * effective_dry + left[i] * effective_wet;
                right[i] = self.dry_buffer_r[i] * effective_dry + right[i] * effective_wet;
            }

            // Snap to target when close enough (avoid denormals)
            if (self.bypass_gain - target_bypass_gain).abs() < 1e-6 {
                self.bypass_gain = target_bypass_gain;
            }

            // P10.0.1: Update output metering AFTER processing + mixing
            self.metering.update_output_levels(&left[..len], &right[..len]);
            self.metering.calculate_gain_reduction();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // P10.0.1: METERING ACCESS METHODS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get current metering data (safe to call from any thread)
    pub fn get_metering(&self) -> ProcessorMetering {
        self.metering
    }

    /// Reset metering to zero
    pub fn reset_metering(&mut self) {
        self.metering.reset();
    }

    /// Reset processor state
    pub fn reset(&mut self) {
        if let Some(ref mut processor) = self.processor {
            processor.reset();
        }
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.bypass_coeff = Self::calculate_bypass_coeff(sample_rate);
        if let Some(ref mut processor) = self.processor {
            processor.set_sample_rate(sample_rate);
            self.latency = processor.latency();
        }
    }

    /// Get processor name
    pub fn name(&self) -> &str {
        self.processor.as_ref().map(|p| p.name()).unwrap_or("Empty")
    }

    /// Set processor parameter (lock-free if processor supports it)
    pub fn set_processor_param(&mut self, index: usize, value: f64) {
        if let Some(ref mut processor) = self.processor {
            processor.set_param(index, value);
        }
    }

    /// Get processor parameter
    pub fn get_processor_param(&self, index: usize) -> f64 {
        self.processor
            .as_ref()
            .map(|p| p.get_param(index))
            .unwrap_or(0.0)
    }

    // ═══ Sidechain Methods (P0.5) ═══

    /// Set sidechain source track (-1 = internal/disabled)
    pub fn set_sidechain_source(&mut self, source_track_id: i64) {
        self.sidechain_source = source_track_id;
    }

    /// Get current sidechain source
    pub fn get_sidechain_source(&self) -> i64 {
        self.sidechain_source
    }

    /// Check if external sidechain is enabled
    pub fn has_external_sidechain(&self) -> bool {
        self.sidechain_source >= 0
    }
}

// ============ Insert Processor Trait ============

/// Trait for insert effect processors
pub trait InsertProcessor: Send + Sync {
    /// Processor name
    fn name(&self) -> &str;

    /// Process stereo audio in-place
    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]);

    /// Process mono audio in-place
    ///
    /// # Warning
    /// Default implementation allocates on heap - not suitable for audio thread!
    /// Implementors should override this with a pre-allocated buffer if mono
    /// processing is needed in real-time context.
    fn process_mono(&mut self, buffer: &mut [Sample]) {
        // Default: process left only (for mono compatibility)
        // NOTE: This default allocates! Override in performance-critical code.
        // Most DAW inserts are stereo, so this is rarely called in audio thread.
        let len = buffer.len().min(MAX_BLEND_BUFFER_SIZE);
        let mut dummy = [0.0_f64; MAX_BLEND_BUFFER_SIZE];
        dummy[..len].copy_from_slice(&buffer[..len]);
        self.process_stereo(&mut buffer[..len], &mut dummy[..len]);
    }

    /// Get latency in samples
    fn latency(&self) -> LatencySamples {
        0
    }

    /// Reset processor state
    fn reset(&mut self);

    /// Set sample rate
    fn set_sample_rate(&mut self, sample_rate: f64);

    /// Get number of parameters
    fn num_params(&self) -> usize {
        0
    }

    /// Get parameter value
    fn get_param(&self, _index: usize) -> f64 {
        0.0
    }

    /// Set parameter value
    fn set_param(&mut self, _index: usize, _value: f64) {}

    /// Get parameter name
    fn param_name(&self, _index: usize) -> &str {
        ""
    }
}

// ============ Insert Chain ============

/// Complete insert chain for a channel
pub struct InsertChain {
    /// Pre-fader slots
    pre_slots: [InsertSlot; MAX_INSERT_SLOTS / 2],
    /// Post-fader slots
    post_slots: [InsertSlot; MAX_INSERT_SLOTS / 2],
    /// Total latency
    total_latency: LatencySamples,
    /// Sample rate
    sample_rate: f64,
}

impl std::fmt::Debug for InsertChain {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("InsertChain")
            .field("total_latency", &self.total_latency)
            .field("sample_rate", &self.sample_rate)
            .field("loaded_slots", &self.loaded_slots())
            .finish()
    }
}

impl InsertChain {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            pre_slots: std::array::from_fn(InsertSlot::new),
            post_slots: std::array::from_fn(|i| InsertSlot::new(i + MAX_INSERT_SLOTS / 2)),
            total_latency: 0,
            sample_rate,
        }
    }

    /// Get slot by index (0-3 = pre, 4-7 = post)
    pub fn slot(&self, index: usize) -> Option<&InsertSlot> {
        if index < MAX_INSERT_SLOTS / 2 {
            Some(&self.pre_slots[index])
        } else if index < MAX_INSERT_SLOTS {
            Some(&self.post_slots[index - MAX_INSERT_SLOTS / 2])
        } else {
            None
        }
    }

    /// Get mutable slot by index
    pub fn slot_mut(&mut self, index: usize) -> Option<&mut InsertSlot> {
        if index < MAX_INSERT_SLOTS / 2 {
            Some(&mut self.pre_slots[index])
        } else if index < MAX_INSERT_SLOTS {
            Some(&mut self.post_slots[index - MAX_INSERT_SLOTS / 2])
        } else {
            None
        }
    }

    /// Load processor into slot
    pub fn load(&mut self, index: usize, processor: Box<dyn InsertProcessor>) -> bool {
        if let Some(slot) = self.slot_mut(index) {
            slot.load(processor);
            self.update_latency();
            true
        } else {
            false
        }
    }

    /// Unload processor from slot
    pub fn unload(&mut self, index: usize) -> Option<Box<dyn InsertProcessor>> {
        let result = self.slot_mut(index).and_then(|s| s.unload());
        self.update_latency();
        result
    }

    /// Process pre-fader slots
    #[inline]
    pub fn process_pre_fader(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for slot in &mut self.pre_slots {
            slot.process(left, right);
        }
    }

    /// Process post-fader slots
    #[inline]
    pub fn process_post_fader(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for slot in &mut self.post_slots {
            slot.process(left, right);
        }
    }

    /// Process all slots (for simple use)
    #[inline]
    pub fn process_all(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.process_pre_fader(left, right);
        self.process_post_fader(left, right);
    }

    /// Update total latency
    fn update_latency(&mut self) {
        self.total_latency = self.pre_slots.iter().map(|s| s.latency()).sum::<usize>()
            + self.post_slots.iter().map(|s| s.latency()).sum::<usize>();
    }

    /// Get total latency
    pub fn total_latency(&self) -> LatencySamples {
        self.total_latency
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for slot in &mut self.pre_slots {
            slot.set_sample_rate(sample_rate);
        }
        for slot in &mut self.post_slots {
            slot.set_sample_rate(sample_rate);
        }
        self.update_latency();
    }

    /// Reset all processors
    pub fn reset(&mut self) {
        for slot in &mut self.pre_slots {
            slot.reset();
        }
        for slot in &mut self.post_slots {
            slot.reset();
        }
    }

    /// Bypass all slots
    pub fn bypass_all(&self, bypass: bool) {
        for slot in &self.pre_slots {
            slot.set_bypass(bypass);
        }
        for slot in &self.post_slots {
            slot.set_bypass(bypass);
        }
    }

    /// Get list of loaded processors
    pub fn loaded_slots(&self) -> Vec<(usize, &str)> {
        let mut result = Vec::new();

        for (i, slot) in self.pre_slots.iter().enumerate() {
            if slot.is_loaded() {
                result.push((i, slot.name()));
            }
        }

        for (i, slot) in self.post_slots.iter().enumerate() {
            if slot.is_loaded() {
                result.push((i + MAX_INSERT_SLOTS / 2, slot.name()));
            }
        }

        result
    }

    /// Set parameter on processor in specific slot
    pub fn set_slot_param(&mut self, slot_index: usize, param_index: usize, value: f64) {
        if let Some(slot) = self.slot_mut(slot_index) {
            slot.set_processor_param(param_index, value);
        }
    }

    /// Get parameter from processor in specific slot
    pub fn get_slot_param(&self, slot_index: usize, param_index: usize) -> f64 {
        self.slot(slot_index)
            .map(|s| s.get_processor_param(param_index))
            .unwrap_or(0.0)
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    struct TestProcessor {
        gain: f64,
    }

    impl TestProcessor {
        fn new(gain: f64) -> Self {
            Self { gain }
        }
    }

    impl InsertProcessor for TestProcessor {
        fn name(&self) -> &str {
            "TestGain"
        }

        fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
            for s in left.iter_mut() {
                *s *= self.gain;
            }
            for s in right.iter_mut() {
                *s *= self.gain;
            }
        }

        fn reset(&mut self) {}
        fn set_sample_rate(&mut self, _: f64) {}
    }

    #[test]
    fn test_insert_slot() {
        let mut slot = InsertSlot::new(0);
        assert!(!slot.is_loaded());

        slot.load(Box::new(TestProcessor::new(0.5)));
        assert!(slot.is_loaded());
        assert_eq!(slot.name(), "TestGain");

        let mut left = vec![1.0; 4];
        let mut right = vec![1.0; 4];
        slot.process(&mut left, &mut right);

        assert!((left[0] - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_insert_chain() {
        let mut chain = InsertChain::new(48000.0);

        // Load processor in slot 0 (pre-fader)
        chain.load(0, Box::new(TestProcessor::new(0.5)));

        let mut left = vec![1.0; 4];
        let mut right = vec![1.0; 4];
        chain.process_pre_fader(&mut left, &mut right);

        assert!((left[0] - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_bypass() {
        let mut slot = InsertSlot::new(0);
        slot.load(Box::new(TestProcessor::new(0.5)));

        // Bypass uses exponential fade - need ~5x time constant for 99% convergence
        // 5ms @ 48kHz = 240 samples, need ~1200 samples for full convergence
        slot.set_bypass(true);

        // Process multiple blocks to complete fade (2048 samples total)
        for _ in 0..32 {
            let mut left = vec![1.0; 64];
            let mut right = vec![1.0; 64];
            slot.process(&mut left, &mut right);
        }

        // After fade completes, signal should pass through unchanged
        let mut left = vec![1.0; 4];
        let mut right = vec![1.0; 4];
        slot.process(&mut left, &mut right);

        // Should be unchanged when fully bypassed (bypass_gain ≈ 0)
        assert!((left[0] - 1.0).abs() < 0.01, "Expected ~1.0, got {}", left[0]);
    }

    #[test]
    fn test_bypass_fade_no_click() {
        let mut slot = InsertSlot::new(0);
        slot.load(Box::new(TestProcessor::new(0.0))); // Zeroes the signal

        // Start active, then bypass - should fade smoothly
        let mut left = vec![1.0; 256];
        let mut right = vec![1.0; 256];
        slot.process(&mut left, &mut right);

        // Signal should be 0 (wet = 0.0)
        assert!(left[255].abs() < 0.01);

        // Now bypass
        slot.set_bypass(true);

        // During fade, output should smoothly transition toward 1.0 (dry)
        let mut left2 = vec![1.0; 256];
        let mut right2 = vec![1.0; 256];
        slot.process(&mut left2, &mut right2);

        // Values should increase (fading toward dry signal)
        assert!(left2[0] > 0.0, "Fade should start immediately");
        assert!(left2[255] > left2[0], "Signal should increase during fade");
    }

    #[test]
    fn test_wet_dry_mix() {
        let mut slot = InsertSlot::new(0);
        slot.load(Box::new(TestProcessor::new(0.0))); // Zeroes the signal
        slot.set_mix(0.5); // 50% wet

        // Process enough samples for bypass_gain to settle at 1.0
        for _ in 0..5 {
            let mut left = vec![1.0; 128];
            let mut right = vec![1.0; 128];
            slot.process(&mut left, &mut right);
        }

        let mut left = vec![1.0; 4];
        let mut right = vec![1.0; 4];
        slot.process(&mut left, &mut right);

        // 50% of 1.0 (dry) + 50% of 0.0 (wet) = 0.5
        assert!((left[3] - 0.5).abs() < 0.01, "Expected ~0.5, got {}", left[3]);
    }
}
